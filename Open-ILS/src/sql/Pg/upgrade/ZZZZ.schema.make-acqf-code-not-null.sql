BEGIN;

-- if there are any straggling funds without a code set, fix that
UPDATE acq.fund
SET code = 'FUND-WITH-ID-' || id
WHERE code IS NULL;

ALTER TABLE acq.fund
    ALTER COLUMN code SET NOT NULL;

COMMIT;
