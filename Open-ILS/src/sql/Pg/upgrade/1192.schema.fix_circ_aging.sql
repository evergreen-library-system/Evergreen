BEGIN;

SELECT evergreen.upgrade_deps_block_check('1192', :eg_version);

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found
    FROM action.circulation
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
	END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables


/* LP 1858448 : Disable initial aged money migration
    INSERT INTO money.aged_billing
        SELECT * FROM money.billing WHERE xact = OLD.id;

    INSERT INTO money.aged_payment 
        SELECT * FROM money.payment_view WHERE xact = OLD.id;

    DELETE FROM money.payment WHERE xact = OLD.id;
    DELETE FROM money.billing WHERE xact = OLD.id;

*/

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

COMMIT;
