--Upgrade Script for 2.10.1 to 2.10.2
\set eg_version '''2.10.2'''
BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.10.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0976', :eg_version);

ALTER TABLE action.usr_circ_history 
    DROP CONSTRAINT IF EXISTS usr_circ_history_target_copy_fkey;

CREATE TRIGGER action_usr_circ_history_target_copy_trig 
    AFTER INSERT OR UPDATE ON action.usr_circ_history 
    FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('target_copy');

SELECT evergreen.upgrade_deps_block_check('0977', :eg_version); -- Callender/Dyrcona/gmcharlt

ALTER TABLE biblio.monograph_part DROP CONSTRAINT "record_label_unique";
CREATE UNIQUE INDEX record_label_unique_idx ON biblio.monograph_part (record, label) WHERE deleted = FALSE;

SELECT evergreen.upgrade_deps_block_check('0978', :eg_version);

-- note: it is not necessary to explicitly drop the previous VARIADIC
-- version of this stored procedure; create or replace function...
-- suffices.
CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting_batch( org_id INT, setting_names TEXT[] ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    setting_name TEXT;
    cur_org INT;
BEGIN
    FOREACH setting_name IN ARRAY setting_names
    LOOP
        cur_org := org_id;
        LOOP
            SELECT INTO setting * FROM actor.org_unit_setting WHERE org_unit = cur_org AND name = setting_name;
            IF FOUND THEN
                RETURN NEXT setting;
                EXIT;
            END IF;
            SELECT INTO cur_org parent_ou FROM actor.org_unit WHERE id = cur_org;
            EXIT WHEN cur_org IS NULL;
        END LOOP;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION actor.org_unit_ancestor_setting_batch( INT,  TEXT[] ) IS $$
For each setting name passed, search "up" the org_unit tree until
we find the first occurrence of an org_unit_setting with the given name.
$$;

COMMIT;
