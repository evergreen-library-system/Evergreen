BEGIN;

CREATE TYPE actor.cascade_setting_summary AS (
    name TEXT,
    value JSON,
    has_org_setting BOOLEAN,
    has_user_setting BOOLEAN,
    has_workstation_setting BOOLEAN
);

SELECT evergreen.upgrade_deps_block_check('1116', :eg_version);

CREATE TABLE config.workstation_setting_type (
    name            TEXT    PRIMARY KEY,
    label           TEXT    UNIQUE NOT NULL,
    grp             TEXT    REFERENCES config.settings_group (name),
    description     TEXT,
    datatype        TEXT    NOT NULL DEFAULT 'string',
    fm_class        TEXT,
    --
    -- define valid datatypes
    --
    CONSTRAINT cwst_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
      'date', 'string', 'object', 'array', 'link' ) ),
    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT cwst_no_empty_link CHECK
    ( ( datatype =  'link' AND fm_class IS NOT NULL ) OR
      ( datatype <> 'link' AND fm_class IS NULL ) )
);

CREATE TABLE actor.workstation_setting (
    id          SERIAL PRIMARY KEY,
    workstation INT    NOT NULL REFERENCES actor.workstation (id) 
                       ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT   NOT NULL REFERENCES config.workstation_setting_type (name) 
                       ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    value       JSON   NOT NULL
);


CREATE INDEX actor_workstation_setting_workstation_idx 
    ON actor.workstation_setting (workstation);

CREATE OR REPLACE FUNCTION config.setting_is_user_or_ws()
RETURNS TRIGGER AS $FUNC$
BEGIN

    IF TG_TABLE_NAME = 'usr_setting_type' THEN
        PERFORM TRUE FROM config.workstation_setting_type cwst
            WHERE cwst.name = NEW.name;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'workstation_setting_type' THEN
        PERFORM TRUE FROM config.usr_setting_type cust
            WHERE cust.name = NEW.name;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    END IF;

    RAISE EXCEPTION 
        '% Cannot be used as both a user setting and a workstation setting.', 
        NEW.name;
END;
$FUNC$ LANGUAGE PLPGSQL STABLE;

CREATE CONSTRAINT TRIGGER check_setting_is_usr_or_ws
  AFTER INSERT OR UPDATE ON config.usr_setting_type
  FOR EACH ROW EXECUTE PROCEDURE config.setting_is_user_or_ws();

CREATE CONSTRAINT TRIGGER check_setting_is_usr_or_ws
  AFTER INSERT OR UPDATE ON config.workstation_setting_type
  FOR EACH ROW EXECUTE PROCEDURE config.setting_is_user_or_ws();

CREATE OR REPLACE FUNCTION actor.get_cascade_setting(
    setting_name TEXT, org_id INT, user_id INT, workstation_id INT) 
    RETURNS actor.cascade_setting_summary AS
$FUNC$
DECLARE
    setting_value JSON;
    summary actor.cascade_setting_summary;
    org_setting_type config.org_unit_setting_type%ROWTYPE;
BEGIN

    summary.name := setting_name;

    -- Collect the org setting type status first in case we exit early.
    -- The existance of an org setting type is not considered
    -- privileged information.
    SELECT INTO org_setting_type * 
        FROM config.org_unit_setting_type WHERE name = setting_name;
    IF FOUND THEN
        summary.has_org_setting := TRUE;
    ELSE
        summary.has_org_setting := FALSE;
    END IF;

    -- User and workstation settings have the same priority.
    -- Start with user settings since that's the simplest code path.
    -- The workstation_id is ignored if no user_id is provided.
    IF user_id IS NOT NULL THEN

        SELECT INTO summary.value value FROM actor.usr_setting
            WHERE usr = user_id AND name = setting_name;

        IF FOUND THEN
            -- if we have a value, we have a setting type
            summary.has_user_setting := TRUE;

            IF workstation_id IS NOT NULL THEN
                -- Only inform the caller about the workstation
                -- setting type disposition when a workstation id is
                -- provided.  Otherwise, it's NULL to indicate UNKNOWN.
                summary.has_workstation_setting := FALSE;
            END IF;

            RETURN summary;
        END IF;

        -- no user setting value, but a setting type may exist
        SELECT INTO summary.has_user_setting EXISTS (
            SELECT TRUE FROM config.usr_setting_type 
            WHERE name = setting_name
        );

        IF workstation_id IS NOT NULL THEN 

            IF NOT summary.has_user_setting THEN
                -- A workstation setting type may only exist when a user
                -- setting type does not.

                SELECT INTO summary.value value 
                    FROM actor.workstation_setting         
                    WHERE workstation = workstation_id AND name = setting_name;

                IF FOUND THEN
                    -- if we have a value, we have a setting type
                    summary.has_workstation_setting := TRUE;
                    RETURN summary;
                END IF;

                -- no value, but a setting type may exist
                SELECT INTO summary.has_workstation_setting EXISTS (
                    SELECT TRUE FROM config.workstation_setting_type 
                    WHERE name = setting_name
                );
            END IF;

            -- Finally make use of the workstation to determine the org
            -- unit if none is provided.
            IF org_id IS NULL AND summary.has_org_setting THEN
                SELECT INTO org_id owning_lib 
                    FROM actor.workstation WHERE id = workstation_id;
            END IF;
        END IF;
    END IF;

    -- Some org unit settings are protected by a view permission.
    -- First see if we have any data that needs protecting, then 
    -- check the permission if needed.

    IF NOT summary.has_org_setting THEN
        RETURN summary;
    END IF;

    -- avoid putting the value into the summary until we confirm
    -- the value should be visible to the caller.
    SELECT INTO setting_value value 
        FROM actor.org_unit_ancestor_setting(setting_name, org_id);

    IF NOT FOUND THEN
        -- No value found -- perm check is irrelevant.
        RETURN summary;
    END IF;

    IF org_setting_type.view_perm IS NOT NULL THEN

        IF user_id IS NULL THEN
            RAISE NOTICE 'Perm check required but no user_id provided';
            RETURN summary;
        END IF;

        IF NOT permission.usr_has_perm(
            user_id, (SELECT code FROM permission.perm_list 
                WHERE id = org_setting_type.view_perm), org_id) 
        THEN
            RAISE NOTICE 'Perm check failed for user % on %',
                user_id, org_setting_type.view_perm;
            RETURN summary;
        END IF;
    END IF;

    -- Perm check succeeded or was not necessary.
    summary.value := setting_value;
    RETURN summary;
END;
$FUNC$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION actor.get_cascade_setting_batch(
    setting_names TEXT[], org_id INT, user_id INT, workstation_id INT) 
    RETURNS SETOF actor.cascade_setting_summary AS
$FUNC$
-- Returns a row per setting matching the setting name order.  If no 
-- value is applied, NULL is returned to retain name-response ordering.
DECLARE
    setting_name TEXT;
    summary actor.cascade_setting_summary;
BEGIN
    FOREACH setting_name IN ARRAY setting_names LOOP
        SELECT INTO summary * FROM actor.get_cascade_setting(
            setting_Name, org_id, user_id, workstation_id);
        RETURN NEXT summary;
    END LOOP;
END;
$FUNC$ LANGUAGE PLPGSQL;

COMMIT;



