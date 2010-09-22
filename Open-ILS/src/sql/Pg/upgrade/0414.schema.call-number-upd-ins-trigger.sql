BEGIN;

-- Adding a trigger.  Upgrade # 0364 created the trigger function but not
-- the trigger itself.  However the base install script 040.schema.asset.sql
-- creates both the function and the trigger.

INSERT INTO config.upgrade_log (version) VALUES ('0414'); -- Scott McKellar

CREATE TRIGGER asset_label_sortkey_trigger
    BEFORE UPDATE OR INSERT ON asset.call_number
    FOR EACH ROW EXECUTE PROCEDURE asset.label_normalizer();

COMMIT;
