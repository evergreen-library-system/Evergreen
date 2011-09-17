-- New tables

CREATE TABLE action.archive_actor_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL,
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

CREATE TABLE action.archive_asset_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL,
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

-- Add columns to existing tables

-- Archive Flag Columns
ALTER TABLE actor.stat_cat
    ADD COLUMN checkout_archive BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE asset.stat_cat
    ADD COLUMN checkout_archive BOOL NOT NULL DEFAULT FALSE;

-- Circulation copy column
ALTER TABLE action.circulation
    ADD COLUMN copy_location INT NOT NULL DEFAULT 1 REFERENCES asset.copy_location(id) DEFERRABLE INITIALLY DEFERRED;

-- Update action.circulation with real copy_location numbers instead of all "Stacks"
UPDATE action.circulation circ SET copy_location = ac.location FROM asset.copy ac WHERE ac.id = circ.target_copy;

-- Create trigger function to auto-fill the copy_location field
CREATE OR REPLACE FUNCTION action.fill_circ_copy_location () RETURNS TRIGGER AS $$
BEGIN
    SELECT INTO NEW.copy_location location FROM asset.copy WHERE id = NEW.target_copy;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Create trigger function to auto-archive stat cat entries
CREATE OR REPLACE FUNCTION action.archive_stat_cats () RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO action.archive_actor_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, asceum.stat_cat, asceum.stat_cat_entry
        FROM actor.stat_cat_entry_usr_map asceum
             JOIN actor.stat_cat sc ON asceum.stat_cat = sc.id
        WHERE NEW.usr = asceum.target_usr AND sc.checkout_archive;
    INSERT INTO action.archive_asset_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, ascecm.stat_cat, asce.value
        FROM asset.stat_cat_entry_copy_map ascecm
             JOIN asset.stat_cat sc ON ascecm.stat_cat = sc.id
             JOIN asset.stat_cat_entry asce ON ascecm.stat_cat_entry = asce.id
        WHERE NEW.target_copy = ascecm.owning_copy AND sc.checkout_archive;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

-- Apply triggers
CREATE TRIGGER fill_circ_copy_location_tgr BEFORE INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.fill_circ_copy_location();
CREATE TRIGGER archive_stat_cats_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.archive_stat_cats();

