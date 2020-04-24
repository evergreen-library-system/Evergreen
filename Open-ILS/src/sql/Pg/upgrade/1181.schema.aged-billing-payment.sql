
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1181', :eg_version);

\qecho Migrating aged billing and payment data.  This might take a while.

CREATE TABLE money.aged_payment (LIKE money.payment INCLUDING INDEXES);
ALTER TABLE money.aged_payment ADD COLUMN payment_type TEXT NOT NULL;

CREATE TABLE money.aged_billing (LIKE money.billing INCLUDING INDEXES);


/* LP 1858448 : Disable initial aged money migration

INSERT INTO money.aged_payment 
    SELECT  mp.* FROM money.payment_view mp
    JOIN action.aged_circulation circ ON (circ.id = mp.xact);

INSERT INTO money.aged_billing
    SELECT mb.* FROM money.billing mb
    JOIN action.aged_circulation circ ON (circ.id = mb.xact);
*/

CREATE OR REPLACE VIEW money.all_payments AS
    SELECT * FROM money.payment_view 
    UNION ALL
    SELECT * FROM money.aged_payment;

CREATE OR REPLACE VIEW money.all_billings AS
    SELECT * FROM money.billing
    UNION ALL
    SELECT * FROM money.aged_billing;

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
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
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


/* LP 1858448 : Disable initial aged money migration

-- NOTE you could COMMIT here then start a new TRANSACTION if desired.

\qecho Deleting aged payments and billings from active payment/billing
\qecho tables.  This may take a while...

ALTER TABLE money.payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.cash_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.check_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_card_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.forgive_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.goods_payment DISABLE TRIGGER mat_summary_del_tgr;

DELETE FROM money.payment WHERE id IN (SELECT id FROM money.aged_payment);

ALTER TABLE money.payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.cash_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.check_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_card_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.forgive_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.goods_payment ENABLE TRIGGER mat_summary_del_tgr;

-- TODO: This approach assumes most of the money.billing rows have been
-- copied to money.aged_billing.  If that is not the case, which would
-- happen if circ anonymization is not enabled, it will be faster to
-- perform a simple delete instead of a truncate/rebuild.

-- Copy all money.billing rows that are not represented in money.aged_billing
CREATE TEMPORARY TABLE tmp_money_billing ON COMMIT DROP AS
    SELECT mb.* FROM money.billing mb
    LEFT JOIN money.aged_billing mab USING (id)
    WHERE mab.id IS NULL;

ALTER TABLE money.billing DISABLE TRIGGER ALL;

-- temporarily remove the foreign key constraint to money.billing on
-- account adjusment.  Needed for money.billing truncate.
ALTER TABLE money.account_adjustment 
    DROP CONSTRAINT account_adjustment_billing_fkey;

TRUNCATE money.billing;

INSERT INTO money.billing SELECT * FROM tmp_money_billing;

ALTER TABLE money.billing ENABLE TRIGGER ALL;
ALTER TABLE money.account_adjustment 
    ADD CONSTRAINT account_adjustment_billing_fkey 
    FOREIGN KEY (billing) REFERENCES money.billing (id);

*/

COMMIT;

-- Good to run after truncating -- OK to run after COMMIT.
/* LP 1858448 : Disable initial aged money migration
ANALYZE money.billing;
*/

