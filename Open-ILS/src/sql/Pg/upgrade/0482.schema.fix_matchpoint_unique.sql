BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0482');

-- Drop old (non-functional) constraints

ALTER TABLE config.circ_matrix_matchpoint
    DROP CONSTRAINT ep_once_per_grp_loc_mod_marc;

ALTER TABLE config.hold_matrix_matchpoint
    DROP CONSTRAINT hous_once_per_grp_loc_mod_marc;

-- Clean up tables before making normalized index

CREATE OR REPLACE FUNCTION action.cleanup_matrix_matchpoints() RETURNS void AS $func$
DECLARE
    temp_row    RECORD;
BEGIN
    -- Circ Matrix
    FOR temp_row IN
        SELECT org_unit, grp, circ_modifier, marc_type, marc_form, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_lower_bound, usr_age_upper_bound, COUNT(id) as rowcount, MIN(id) as firstrow
        FROM config.circ_matrix_matchpoint
        WHERE active
        GROUP BY org_unit, grp, circ_modifier, marc_type, marc_form, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_lower_bound, usr_age_upper_bound
        HAVING COUNT(id) > 1 LOOP

        UPDATE config.circ_matrix_matchpoint SET active=false
            WHERE id > temp_row.firstrow
                AND org_unit = temp_row.org_unit
                AND grp = temp_row.grp
                AND circ_modifier       IS NOT DISTINCT FROM temp_row.circ_modifier
                AND marc_type           IS NOT DISTINCT FROM temp_row.marc_type
                AND marc_form           IS NOT DISTINCT FROM temp_row.marc_form
                AND marc_vr_format      IS NOT DISTINCT FROM temp_row.marc_vr_format
                AND copy_circ_lib       IS NOT DISTINCT FROM temp_row.copy_circ_lib
                AND copy_owning_lib     IS NOT DISTINCT FROM temp_row.copy_owning_lib
                AND user_home_ou        IS NOT DISTINCT FROM temp_row.user_home_ou
                AND ref_flag            IS NOT DISTINCT FROM temp_row.ref_flag
                AND juvenile_flag       IS NOT DISTINCT FROM temp_row.juvenile_flag
                AND is_renewal          IS NOT DISTINCT FROM temp_row.is_renewal
                AND usr_age_lower_bound IS NOT DISTINCT FROM temp_row.usr_age_lower_bound
                AND usr_age_upper_bound IS NOT DISTINCT FROM temp_row.usr_age_upper_bound;
    END LOOP;

    -- Hold Matrix
    FOR temp_row IN
        SELECT user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_vr_format, juvenile_flag, ref_flag, COUNT(id) as rowcount, MIN(id) as firstrow
        FROM config.hold_matrix_matchpoint
        WHERE active
        GROUP BY user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_vr_format, juvenile_flag, ref_flag
        HAVING COUNT(id) > 1 LOOP

        UPDATE config.hold_matrix_matchpoint SET active=false
            WHERE id > temp_row.firstrow
                AND user_home_ou        IS NOT DISTINCT FROM temp_row.user_home_ou
                AND request_ou          IS NOT DISTINCT FROM temp_row.request_ou
                AND pickup_ou           IS NOT DISTINCT FROM temp_row.pickup_ou
                AND item_owning_ou      IS NOT DISTINCT FROM temp_row.item_owning_ou
                AND item_circ_ou        IS NOT DISTINCT FROM temp_row.item_circ_ou
                AND usr_grp             IS NOT DISTINCT FROM temp_row.usr_grp
                AND requestor_grp       IS NOT DISTINCT FROM temp_row.requestor_grp
                AND circ_modifier       IS NOT DISTINCT FROM temp_row.circ_modifier
                AND marc_type           IS NOT DISTINCT FROM temp_row.marc_type
                AND marc_form           IS NOT DISTINCT FROM temp_row.marc_form
                AND marc_vr_format      IS NOT DISTINCT FROM temp_row.marc_vr_format
                AND juvenile_flag       IS NOT DISTINCT FROM temp_row.juvenile_flag
                AND ref_flag            IS NOT DISTINCT FROM temp_row.ref_flag;
    END LOOP;
END;
$func$ LANGUAGE plpgsql;

SELECT action.cleanup_matrix_matchpoints();

DROP FUNCTION IF EXISTS action.cleanup_matrix_matchpoints();

-- Create Normalized indexes

CREATE UNIQUE INDEX ccmm_once_per_paramset ON config.circ_matrix_matchpoint (org_unit, grp, COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_vr_format, ''), COALESCE(copy_circ_lib::TEXT, ''), COALESCE(copy_owning_lib::TEXT, ''), COALESCE(user_home_ou::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(is_renewal::TEXT, ''), COALESCE(usr_age_lower_bound::TEXT, ''), COALESCE(usr_age_upper_bound::TEXT, '')) WHERE active;

CREATE UNIQUE INDEX chmm_once_per_paramset ON config.hold_matrix_matchpoint (COALESCE(user_home_ou::TEXT, ''), COALESCE(request_ou::TEXT, ''), COALESCE(pickup_ou::TEXT, ''), COALESCE(item_owning_ou::TEXT, ''), COALESCE(item_circ_ou::TEXT, ''), COALESCE(usr_grp::TEXT, ''), COALESCE(requestor_grp::TEXT, ''), COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_vr_format, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(ref_flag::TEXT, '')) WHERE active;

COMMIT;
