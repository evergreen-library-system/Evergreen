BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0511'); -- miker

CREATE OR REPLACE FUNCTION evergreen.fake_fkey_tgr () RETURNS TRIGGER AS $F$
DECLARE
    copy_id BIGINT;
BEGIN
    EXECUTE 'SELECT ($1).' || quote_ident(TG_ARGV[0]) INTO copy_id USING NEW;
    PERFORM * FROM asset.copy WHERE id = copy_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Key (%.%=%) does not exist in asset.copy', TG_TABLE_SCHEMA, TG_TABLE_NAME, copy_id;
    END IF;
    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;

CREATE TRIGGER action_circulation_target_copy_trig AFTER INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('target_copy');

COMMIT;

