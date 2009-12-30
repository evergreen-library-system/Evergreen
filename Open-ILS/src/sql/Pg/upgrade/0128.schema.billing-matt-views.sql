BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0128');

DROP VIEW money.open_usr_circulation_summary;
DROP VIEW money.open_usr_summary;
DROP VIEW money.open_billable_xact_summary;

CREATE OR REPLACE VIEW money.billable_xact_summary AS 
    SELECT * FROM money.materialized_billable_xact_summary;

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS 
    SELECT * FROM money.billable_xact_summary_location_view
    WHERE xact_finish IS NULL;

CREATE OR REPLACE VIEW money.open_usr_circulation_summary AS
    SELECT 
        usr,
        SUM(total_paid) AS total_paid,
        SUM(total_owed) AS total_owed,
        SUM(balance_owed) AS balance_owed
    FROM  money.materialized_billable_xact_summary
    WHERE xact_type = 'circulation' AND xact_finish IS NULL
    GROUP BY usr;

CREATE OR REPLACE VIEW money.usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    GROUP BY usr;

CREATE OR REPLACE VIEW money.open_usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL
    GROUP BY usr;

COMMIT;
