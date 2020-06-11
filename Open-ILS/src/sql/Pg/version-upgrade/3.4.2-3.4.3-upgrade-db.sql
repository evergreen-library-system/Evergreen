--Upgrade Script for 3.4.2 to 3.4.3
\set eg_version '''3.4.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.4.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1202', :eg_version);

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'history.money.age_with_circs',
    NULL, 
    FALSE,
    oils_i18n_gettext(
        'history.money.age_with_circs',
        'Age billings and payments when cirulcations are aged.',
        'cgf', 'label'
    )
), (
    'history.money.retention_age',
    NULL, 
    FALSE,
    oils_i18n_gettext(
        'history.money.retention_age',
        'Age billings and payments whose transactions were completed ' ||
        'this long ago.  For circulation transactions, this setting ' ||
        'is superseded by the "history.money.age_with_circs" setting',
        'cgf', 'label'
    )
);

DROP VIEW money.all_payments;

CREATE OR REPLACE VIEW money.payment_view_for_aging AS
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
    SELECT * FROM money.payment_view_for_aging
    UNION ALL
    SELECT * FROM money.aged_payment;

CREATE OR REPLACE FUNCTION money.age_billings_and_payments() RETURNS INTEGER AS $FUNC$
-- Age billings and payments linked to transactions which were 
-- completed at least 'older_than' time ago.
DECLARE
    xact_id BIGINT;
    counter INTEGER DEFAULT 0;
    keep_age INTERVAL;
BEGIN

    SELECT value::INTERVAL INTO keep_age FROM config.global_flag 
        WHERE name = 'history.money.retention_age' AND enabled;

    -- Confirm interval-based aging is enabled.
    IF keep_age IS NULL THEN RETURN counter; END IF;

    -- Start with non-circulation transactions
    FOR xact_id IN SELECT DISTINCT(xact.id) FROM money.billable_xact xact
        -- confirm there is something to age
        JOIN money.billing mb ON mb.xact = xact.id
        -- Avoid aging money linked to non-aged circulations.
        LEFT JOIN action.circulation circ ON circ.id = xact.id
        WHERE circ.id IS NULL AND AGE(NOW(), xact.xact_finish) > keep_age LOOP

        PERFORM money.age_billings_and_payments_for_xact(xact_id);
        counter := counter + 1;
    END LOOP;

    -- Then handle aged circulation money.
    FOR xact_id IN SELECT DISTINCT(xact.id) FROM action.aged_circulation xact
        -- confirm there is something to age
        JOIN money.billing mb ON mb.xact = xact.id
        WHERE AGE(NOW(), xact.xact_finish) > keep_age LOOP

        PERFORM money.age_billings_and_payments_for_xact(xact_id);
        counter := counter + 1;
    END LOOP;

    RETURN counter;
END;
$FUNC$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION money.age_billings_and_payments_for_xact
    (xact_id BIGINT) RETURNS VOID AS $FUNC$

    INSERT INTO money.aged_billing
        SELECT * FROM money.billing WHERE xact = $1;

    INSERT INTO money.aged_payment 
        SELECT * FROM money.payment_view_for_aging WHERE xact = xact_id;

    DELETE FROM money.payment WHERE xact = $1;
    DELETE FROM money.billing WHERE xact = $1;

$FUNC$ LANGUAGE SQL;

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

    SELECT 'Y' INTO found FROM config.global_flag 
        WHERE name = 'history.money.age_with_circs' AND enabled;

    IF found = 'Y' THEN
        PERFORM money.age_billings_and_payments_for_xact(OLD.id);
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

SELECT evergreen.upgrade_deps_block_check('1204', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 621, 'VIEW_BOOKING_RESOURCE_TYPE', oils_i18n_gettext(621,
    'View booking resource types', 'ppl', 'description')),
 ( 622, 'VIEW_BOOKING_RESOURCE', oils_i18n_gettext(622,
    'View booking resources', 'ppl', 'description'))
;

COMMIT;
