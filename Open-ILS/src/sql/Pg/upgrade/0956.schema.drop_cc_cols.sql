BEGIN;

SELECT evergreen.upgrade_deps_block_check('0956', :eg_version);

ALTER TABLE money.credit_card_payment 
    DROP COLUMN cc_type,
    DROP COLUMN expire_month,
    DROP COLUMN expire_year,
    DROP COLUMN cc_first_name,
    DROP COLUMN cc_last_name;

COMMIT;

