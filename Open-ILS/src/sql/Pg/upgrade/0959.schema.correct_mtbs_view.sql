BEGIN;

SELECT evergreen.upgrade_deps_block_check('0959', :eg_version);

CREATE OR REPLACE VIEW money.transaction_billing_summary AS
    SELECT id as xact,
        last_billing_type,
        last_billing_note,
        last_billing_ts,
        total_owed
      FROM money.materialized_billable_xact_summary;

COMMIT;
