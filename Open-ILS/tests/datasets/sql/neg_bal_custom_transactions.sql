-- DATA FOR LIVE TESTING LP#1198465:
--   Support for Conditional Negative Balances
--
-- Assume stock data has been loaded.
--
-- Dates are relative when necessary; otherwise they may be hardcoded.
-- NOTE: Org unit settings will be handled in the perl code


-- Setup some LOST circs, and change copy status to LOST
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
WHERE id IN (1,2,3,4,5,6,12,13,15);
UPDATE asset.copy SET status = 3 WHERE id IN (2,3,4,5,6,7,13,14,16);

-- relative LOST circ
UPDATE action.circulation SET
    xact_start = NOW() - '24 days'::interval,
    due_date = (DATE(NOW() - '10 days'::interval) || ' 23:59:59')::TIMESTAMP,
    stop_fines_time = NOW() - '3 days'::interval,
    create_time = NOW() - '24 days'::interval,
    max_fine = '5.00',
    stop_fines = 'LOST',
    checkin_staff = NULL,
    checkin_lib = NULL,
    checkin_time = NULL,
    checkin_scan_time = NULL
WHERE id = 10;
UPDATE asset.copy SET status = 3 WHERE id = 11;

-- Two recently LOST items for Case 10: Interval Testing (1 hour interval)
-- - Item 1: Lost, paid more than 1 hour later, to be returned LESS than 1 hour after payment (via perl test)
-- - Item 2: Lost, paid more than 1 hour later, to be returned MORE than 1 hour after payment (via perl test)
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

-- non-lost circs, used for Amnesty Mode check-ins
UPDATE action.circulation SET
    xact_start = '2014-05-14 08:39:13.070326-04',
    due_date = '2014-05-21 23:59:59-04',
    stop_fines_time = '2014-05-28 08:39:13.070326-04',
    create_time = '2014-05-14 08:39:13.070326-04',
    max_fine = '0.70',
    stop_fines = 'MAXFINES',
    checkin_staff = NULL,
    checkin_lib = NULL,
    checkin_time = NULL,
    checkin_scan_time = NULL
WHERE id IN (7, 14, 16);
UPDATE asset.copy SET status = 1 WHERE id IN (8, 15, 17);

-- Setup a non-lost, maxfines circ
UPDATE action.circulation SET
    xact_start = '2014-05-14 08:39:13.070326-04',
    due_date = '2014-05-21 23:59:59-04',
    stop_fines_time = '2014-05-28 08:39:13.070326-04',
    create_time = '2014-05-14 08:39:13.070326-04',
    max_fine = '0.70',
    stop_fines = 'MAXFINES',
    checkin_staff = NULL,
    checkin_lib = NULL,
    checkin_time = NULL,
    checkin_scan_time = NULL
WHERE id = 11;
UPDATE asset.copy SET status = 1 WHERE id = 12;


-- Create LOST and overdue fines
INSERT INTO money.billing (id, xact, create_date, voided, voider, void_time, amount, billing_type, btype, note, period_start, period_end) VALUES
    (DEFAULT, 1, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 2, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 3, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 4, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 6, '2014-05-22 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 6, '2014-05-23 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 6, '2014-05-24 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 6, '2014-05-25 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 6, '2014-05-26 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 6, '2014-05-27 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 6, '2014-05-28 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    (DEFAULT, 6, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 7, '2014-05-22 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 7, '2014-05-23 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 7, '2014-05-24 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 7, '2014-05-25 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 7, '2014-05-26 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 7, '2014-05-27 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 7, '2014-05-28 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    (DEFAULT, 8, NOW() - '2 hours'::interval, false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 9, NOW() - '4 hours'::interval, false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 11, '2014-05-22 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 11, '2014-05-23 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 11, '2014-05-24 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 11, '2014-05-25 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 11, '2014-05-26 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 11, '2014-05-27 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 11, '2014-05-28 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    (DEFAULT, 12, '2014-05-22 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 12, '2014-05-23 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 12, '2014-05-24 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 12, '2014-05-25 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 12, '2014-05-26 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 12, '2014-05-27 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 12, '2014-05-28 00:00:00-04', true, 1, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    (DEFAULT, 12, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 13, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 14, '2014-05-22 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 14, '2014-05-23 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 14, '2014-05-24 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 14, '2014-05-25 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 14, '2014-05-26 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 14, '2014-05-27 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 14, '2014-05-28 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    (DEFAULT, 15, '2014-05-28 08:39:13.070326-04', false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL),
    (DEFAULT, 16, '2014-05-22 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 16, '2014-05-23 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 16, '2014-05-24 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 16, '2014-05-25 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 16, '2014-05-26 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 16, '2014-05-27 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 16, '2014-05-28 00:00:00-04', false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    -- XACTS 5 and 10 must be last, because we use CURRVAL() to put their IDs in the account adjustments
    (DEFAULT, 5, '2014-05-22 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-22 00:00:00-04', '2014-05-22 23:59:59-04'),
    (DEFAULT, 5, '2014-05-23 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-23 00:00:00-04', '2014-05-23 23:59:59-04'),
    (DEFAULT, 5, '2014-05-24 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-24 00:00:00-04', '2014-05-24 23:59:59-04'),
    (DEFAULT, 5, '2014-05-25 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-25 00:00:00-04', '2014-05-25 23:59:59-04'),
    (DEFAULT, 5, '2014-05-26 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-26 00:00:00-04', '2014-05-26 23:59:59-04'),
    (DEFAULT, 5, '2014-05-27 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-27 00:00:00-04', '2014-05-27 23:59:59-04'),
    (DEFAULT, 5, '2014-05-28 00:00:00-04', false, NULL, '2014-05-28 08:39:13.070326-04', 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', '2014-05-28 00:00:00-04', '2014-05-28 23:59:59-04'),
    (DEFAULT, 10, (DATE(NOW() - '9 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '9 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '9 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, (DATE(NOW() - '8 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '8 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '8 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, (DATE(NOW() - '7 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '7 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '7 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, (DATE(NOW() - '6 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '6 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '6 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, (DATE(NOW() - '5 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '5 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '5 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, (DATE(NOW() - '4 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '4 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '4 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, (DATE(NOW() - '3 days'::interval) || ' 00:00:00')::TIMESTAMP, false, NULL, NULL, 0.10, 'Overdue materials', 1, 'System Generated Overdue Fine', (DATE(NOW() - '9 days'::interval) || ' 00:00:00')::TIMESTAMP, (DATE(NOW() - '9 days'::interval) || ' 23:59:59')::TIMESTAMP),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, NULL, NULL, 50.00, 'Lost Materials', 3, 'SYSTEM GENERATED', NULL, NULL);


INSERT INTO money.account_adjustment (id, xact, payment_ts, voided, amount, note, amount_collected, accepting_usr, billing) VALUES
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 14),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 13),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 12),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 11),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 10),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 9),
    (DEFAULT, 5, '2014-05-28 08:39:13.070326-04', false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 8),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 7),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 6),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 5),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 4),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 3),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 2),
    (DEFAULT, 10, NOW() - '3 days'::interval, false, 0.10, '', 0.10, 1, CURRVAL('money.billing_id_seq') - 1);

INSERT INTO money.cash_payment (id, xact, payment_ts, voided, amount, note, amount_collected, accepting_usr, cash_drawer) VALUES
    (DEFAULT, 8, NOW() - '30 minutes'::interval, false, 50.00, 'LOST payment', 50.00, 1, 51),
    (DEFAULT, 9, NOW() - '2 hours'::interval, false, 50.00, 'LOST payment', 50.00, 1, 51),
    (DEFAULT, 10, NOW() - '2 days'::interval, false, 10.00, 'Partial LOST payment', 10.00, 1, 51);

-- if rerunning, make sure our mangled bills have the right total in the summary
UPDATE money.materialized_billable_xact_summary SET balance_owed = 50.00
    WHERE id IN (1,2,3,4,5,6,12,13,15);
UPDATE money.materialized_billable_xact_summary SET balance_owed = 0.70
    WHERE id IN (7, 14, 16);
UPDATE money.materialized_billable_xact_summary SET balance_owed = 0.00
    WHERE id IN (8, 9);
UPDATE money.materialized_billable_xact_summary SET balance_owed = 40.00
    WHERE id = 10;
UPDATE money.materialized_billable_xact_summary SET balance_owed = 0.70
    WHERE id = 11;
