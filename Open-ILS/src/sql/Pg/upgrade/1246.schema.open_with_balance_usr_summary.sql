BEGIN;

SELECT evergreen.upgrade_deps_block_check('1246', :eg_version);

CREATE OR REPLACE VIEW money.open_with_balance_usr_summary AS
    SELECT
        usr,
        sum(total_paid) AS total_paid,
        sum(total_owed) AS total_owed,
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL AND balance_owed <> 0.0
    GROUP BY usr;

COMMIT;
