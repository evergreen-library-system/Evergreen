BEGIN;

SELECT evergreen.upgrade_deps_block_check('1188', :eg_version);

UPDATE action.circulation SET auto_renewal = FALSE WHERE auto_renewal IS NULL;

UPDATE action.aged_circulation SET auto_renewal = FALSE WHERE auto_renewal IS NULL;

COMMIT;

-- The following two changes cannot occur in a transaction with the
-- above updates because we will get an error about not being able to
-- alter a table with pending transactions.  They also need to occur
-- after the above updates or the SET NOT NULL change will fail.

ALTER TABLE action.circulation ALTER COLUMN auto_renewal SET DEFAULT FALSE;
ALTER TABLE action.circulation ALTER COLUMN auto_renewal SET NOT NULL;

ALTER TABLE action.aged_circulation ALTER COLUMN auto_renewal SET DEFAULT FALSE;
ALTER TABLE action.aged_circulation ALTER COLUMN auto_renewal SET NOT NULL;
