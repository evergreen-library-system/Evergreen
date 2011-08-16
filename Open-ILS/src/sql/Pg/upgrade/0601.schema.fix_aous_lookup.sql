-- Evergreen DB patch XXXX.fix_aous_lookup.sql
--
-- Correct actor.org_unit_ancestor_setting so that it returns
-- at most one setting value, rather than the entire set
-- of values defined for the OU and its ancestors.
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0601', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting( setting_name TEXT, org_id INT ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    cur_org INT;
BEGIN
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
    RETURN;
END;
$$ LANGUAGE plpgsql STABLE ROWS 1;


COMMIT;
