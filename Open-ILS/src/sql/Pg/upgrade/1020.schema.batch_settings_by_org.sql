BEGIN;

SELECT evergreen.upgrade_deps_block_check('1020', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting_batch_by_org(
    setting_name TEXT, org_ids INTEGER[]) 
    RETURNS SETOF actor.org_unit_setting AS 
$FUNK$
DECLARE
    setting RECORD;
    org_id INTEGER;
BEGIN
    /*  Returns one actor.org_unit_setting row per org unit ID provided.
        When no setting exists for a given org unit, the setting row
        will contain all empty values. */
    FOREACH org_id IN ARRAY org_ids LOOP
        SELECT INTO setting * FROM 
            actor.org_unit_ancestor_setting(setting_name, org_id);
        RETURN NEXT setting;
    END LOOP;
    RETURN;
END;
$FUNK$ LANGUAGE plpgsql STABLE;

COMMIT;

