BEGIN;

-- RESET DATA FOR LIVE TESTING LP#1198465:
--   Support for Conditional Negative Balances
--
--   After running this, reload neg_bal_custom_transactions.sql.
--   Once both files are run, the tests should succeed again.

-- clear bills and payments for our test circs
DELETE FROM money.billing WHERE xact <= 16;
DELETE FROM money.payment WHERE xact <= 16;

-- clear any non-stock settings
-- XXX This will need adjusting if new stock settings are added, so
-- TODO: Pad out org_unit_settings with a SETVAL like we do for other
-- settings
DELETE FROM actor.org_unit_setting WHERE id >= 14;

-- clear out the test workstation (just in case)
DELETE FROM actor.workstation WHERE name = 'BR1-test-09-lp1198465_neg_balances.t';

COMMIT;
