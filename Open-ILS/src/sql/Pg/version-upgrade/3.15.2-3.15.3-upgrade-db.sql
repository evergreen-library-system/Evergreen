--Upgrade Script for 3.15.2 to 3.15.3
\set eg_version '''3.15.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.15.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1474', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_org_unit_copies ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
    rec             vandelay.bib_match%ROWTYPE;
    v_owning_lib    INT;
    scope_org       INT;
    scope_orgs      INT[];
    copy_count      INT := 0;
    max_copy_count  INT := 0;
BEGIN

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    -- Gather all the owning libs for our import items.
    -- These are our initial scope_orgs.
    SELECT ARRAY_AGG(DISTINCT owning_lib) INTO scope_orgs
        FROM vandelay.import_item
        WHERE record = import_id;

    WHILE CARDINALITY(scope_orgs) IS NOT NULL LOOP
        EXIT WHEN CARDINALITY(scope_orgs) = 0;
        FOR scope_org IN SELECT * FROM UNNEST(scope_orgs) LOOP
            -- For each match, get a count of all copies at descendants of our scope org.
            FOR rec IN SELECT * FROM vandelay.bib_match AS vbm
                WHERE queued_record = import_id
                ORDER BY vbm.eg_record DESC
            LOOP
                SELECT COUNT(acp.id) INTO copy_count
                    FROM asset.copy AS acp
                    INNER JOIN asset.call_number AS acn
                        ON acp.call_number = acn.id
                    WHERE acn.owning_lib IN (SELECT id FROM
                        actor.org_unit_descendants(scope_org))
                    AND acn.record = rec.eg_record
                    AND acp.deleted = FALSE;
                IF copy_count > max_copy_count THEN
                    max_copy_count := copy_count;
                    eg_id := rec.eg_record;
                END IF;
            END LOOP;
        END LOOP;

        EXIT WHEN eg_id IS NOT NULL;

        -- If no matching bibs had holdings, gather our next set of orgs to check, and iterate.
        IF max_copy_count = 0 THEN 
            SELECT ARRAY_AGG(DISTINCT parent_ou) INTO scope_orgs
                FROM actor.org_unit
                WHERE id IN (SELECT * FROM UNNEST(scope_orgs))
                AND parent_ou IS NOT NULL;
            EXIT WHEN CARDINALITY(scope_orgs) IS NULL;
        END IF;
    END LOOP;

    IF eg_id IS NULL THEN
        -- Could not determine best match via copy count
        -- fall back to default best match
        IF (SELECT * FROM vandelay.auto_overlay_bib_record_with_best( import_id, merge_profile_id, lwm_ratio_value_p )) THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1475', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.config.standing_penalty', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.standing_penalty',
        'Grid Config: admin.local.config.standing_penalty',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1476', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, label, description, datatype, fm_class)
VALUES (
    'eg.circ.patron.search.ou',
    'circ',
    oils_i18n_gettext(
        'eg.circ.patron.search.ou',
        'Staff Client patron search: home organization unit',
        'cwst', 'label'),
    oils_i18n_gettext(
        'eg.circ.patron.search.ou',
        'Specifies the home organization unit for patron search',
        'cwst', 'description'),
    'link',
    'aou'
    );

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
