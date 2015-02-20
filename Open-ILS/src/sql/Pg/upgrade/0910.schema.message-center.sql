BEGIN;

SELECT evergreen.upgrade_deps_block_check('0910', :eg_version);

CREATE TABLE actor.usr_message (
    id          SERIAL                      PRIMARY KEY,
    usr         INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    title       TEXT,
    message     TEXT                        NOT NULL,
    create_date TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    deleted     BOOL                        NOT NULL DEFAULT FALSE,
    read_date   TIMESTAMP WITH TIME ZONE,
    sending_lib INT                         NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX aum_usr ON actor.usr_message (usr);

CREATE RULE protect_usr_message_delete AS
    ON DELETE TO actor.usr_message DO INSTEAD (
        UPDATE actor.usr_message
            SET deleted = TRUE
            WHERE OLD.id = actor.usr_message.id
    );

ALTER TABLE action_trigger.event_definition
    ADD COLUMN message_template TEXT,
    ADD COLUMN message_usr_path TEXT,
    ADD COLUMN message_library_path TEXT,
    ADD COLUMN message_title TEXT;

CREATE FUNCTION actor.convert_usr_note_to_message () RETURNS TRIGGER AS $$
BEGIN
    IF NEW.pub THEN
        IF TG_OP = 'UPDATE' THEN
            IF OLD.pub = TRUE THEN
                RETURN NEW;
            END IF;
        END IF;

        INSERT INTO actor.usr_message (usr, title, message, sending_lib)
            VALUES (NEW.usr, NEW.title, NEW.value, (SELECT home_ou FROM actor.usr WHERE id = NEW.creator));
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER convert_usr_note_to_message_tgr
    AFTER INSERT OR UPDATE ON actor.usr_note
    FOR EACH ROW EXECUTE PROCEDURE actor.convert_usr_note_to_message();

CREATE VIEW actor.usr_message_limited
AS SELECT * FROM actor.usr_message;

CREATE FUNCTION actor.restrict_usr_message_limited () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        UPDATE actor.usr_message
        SET    read_date = NEW.read_date,
               deleted   = NEW.deleted
        WHERE  id = NEW.id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER restrict_usr_message_limited_tgr
    INSTEAD OF UPDATE OR INSERT OR DELETE ON actor.usr_message_limited
    FOR EACH ROW EXECUTE PROCEDURE actor.restrict_usr_message_limited();

-- and copy over existing public user notes as (read) patron messages
INSERT INTO actor.usr_message (usr, title, message, sending_lib, create_date, read_date)
SELECT aun.usr, title, value, home_ou, aun.create_date, NOW()
FROM actor.usr_note aun
JOIN actor.usr au ON (au.id = aun.usr)
WHERE aun.pub;

COMMIT;

