BEGIN;

-- DATA FOR LIVE TESTING LP#1198465:
--   Support for Conditional Negative Balances
--
-- Assume stock data has been loaded.
--
-- Dates are relative when necessary; otherwise they may be hardcoded.
-- NOTE: Org unit settings will be handled in the perl code


-- user id: 4, name: Gregory Jones

-- clear bills and payments for our test circs
DELETE FROM money.billing WHERE xact <= 9;
DELETE FROM money.payment WHERE xact <= 9;

-- clear any non-stock settings
-- XXX This will need adjusting if new stock settings are added, so
-- TODO: Pad out org_unit_settings with a SETVAL like we do for other
-- settings
DELETE FROM actor.org_unit_setting WHERE id >= 14;

-- clear out the test workstation (just in case)
DELETE FROM actor.workstation WHERE name = 'BR1-test-09-lp1198465_neg_balances.t';

-- Setup all LOST circs
UPDATE action.circulation SET
    xact_start = '2014-05-14 08:39:13.070326-04',
	due_date = '2014-05-21 23:59:59-04',
	stop_fines_time = '2014-05-28 08:39:13.070326-04',
	create_time = '2014-05-14 08:39:13.070326-04',
	max_fine = '3.00',
	stop_fines = 'LOST',
	checkin_staff = NULL,
	checkin_lib = NULL,
	checkin_time = NULL,
	checkin_scan_time = NULL
WHERE id >= 1 AND id <= 6;
UPDATE asset.copy SET status = 3 WHERE id >= 2 AND id <= 7;

-- Setup non-lost circ
UPDATE action.circulation SET
	checkin_staff = NULL,
	checkin_lib = NULL,
	checkin_time = NULL,
	checkin_scan_time = NULL,
	stop_fines = NULL,
	stop_fines_time = NULL
WHERE id = 7;
UPDATE asset.copy SET status = 1 WHERE id = 8;

-- Setup other LOST and overdue fines
INSERT INTO money.billing (id, xact, billing_ts, voided, voider, void_time, amount, billing_type, btype, note) VALUES
    (DEFAULT, 1, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 2, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 3, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 4, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 6, '2014-05-22 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-23 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-24 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-25 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-26 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-27 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-28 23:59:59-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 6, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 7, '2014-05-22 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 7, '2014-05-23 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 7, '2014-05-24 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 7, '2014-05-25 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 7, '2014-05-26 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 7, '2014-05-27 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine'),
    (DEFAULT, 7, '2014-05-28 23:59:59-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine');

-- Setup two recently LOST items for Case 10: Interval Testing
-- - Item 1: Lost, paid more than 1 hour later, returned less than 1 hour after payment (via perl test)
-- - Item 2: Lost, paid more than 1 hour later, returned more than 1 hour after payment (via perl test)
UPDATE action.circulation SET
	create_time = NOW() - '1 week'::interval,
    xact_start = NOW() - '1 week'::interval,
	due_date = NOW() + '1 day'::interval,
	stop_fines_time = NOW() - '3 hours'::interval,
	max_fine = '3.00',
	stop_fines = 'LOST',
	checkin_staff = NULL,
	checkin_lib = NULL,
	checkin_time = NULL,
	checkin_scan_time = NULL
WHERE id IN (8, 9);
UPDATE asset.copy SET status = 3 WHERE id IN (9, 10);

INSERT INTO money.billing (id, xact, billing_ts, voided, voider, void_time, amount, billing_type, btype, note) VALUES
    (DEFAULT, 8, NOW() - '2 hours'::interval, false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED'),
    (DEFAULT, 9, NOW() - '4 hours'::interval, false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED');

INSERT INTO money.payment (id, xact, payment_ts, voided, amount, note) VALUES
	(DEFAULT, 8, NOW() - '30 minutes'::interval, false, 50.00, 'LOST payment'),
	(DEFAULT, 9, NOW() - '2 hours'::interval, false, 50.00, 'LOST payment');

-- if rerunning, make sure our mangled bills have the right total in the summary
UPDATE money.materialized_billable_xact_summary SET balance_owed = 50.00
	WHERE id >=1 AND id <= 6;
UPDATE money.materialized_billable_xact_summary SET balance_owed = 0.70
	WHERE id = 7;
UPDATE money.materialized_billable_xact_summary SET balance_owed = 0.00
	WHERE id IN (8, 9);

COMMIT;
