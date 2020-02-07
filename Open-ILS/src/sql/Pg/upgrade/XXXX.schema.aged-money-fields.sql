BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

DROP VIEW money.all_payments;

CREATE OR REPLACE VIEW money.payment_view_extended AS
    SELECT p.*,
        bnm.accepting_usr,
        bnmd.cash_drawer,
        maa.billing
    FROM money.payment_view p
    LEFT JOIN money.bnm_payment bnm ON bnm.id = p.id
    LEFT JOIN money.bnm_desk_payment bnmd ON bnmd.id = p.id
    LEFT JOIN money.account_adjustment maa ON maa.id = p.id;

ALTER TABLE money.aged_payment
    ADD COLUMN accepting_usr INTEGER,
    ADD COLUMN cash_drawer INTEGER,
    ADD COLUMN billing BIGINT;

CREATE INDEX aged_payment_accepting_usr_idx ON money.aged_payment(accepting_usr);
CREATE INDEX aged_payment_cash_drawer_idx ON money.aged_payment(cash_drawer);
CREATE INDEX aged_payment_billing_idx ON money.aged_payment(billing);

CREATE OR REPLACE VIEW money.all_payments AS
    SELECT * FROM money.payment_view_extended
    UNION ALL
    SELECT * FROM money.aged_payment;

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

    INSERT INTO money.aged_billing
        SELECT * FROM money.billing WHERE xact = OLD.id;

    INSERT INTO money.aged_payment 
        SELECT * FROM money.payment_view_extended WHERE xact = OLD.id;

    DELETE FROM money.payment WHERE xact = OLD.id;
    DELETE FROM money.billing WHERE xact = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';


COMMIT;
