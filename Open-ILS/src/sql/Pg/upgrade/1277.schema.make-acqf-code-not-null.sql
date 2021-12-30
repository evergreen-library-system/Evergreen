BEGIN;

SELECT evergreen.upgrade_deps_block_check('1277', :eg_version);

-- if there are any straggling funds without a code set, fix that
UPDATE acq.fund
SET code = 'FUND-WITH-ID-' || id
WHERE code IS NULL;

ALTER TABLE acq.fund
    ALTER COLUMN code SET NOT NULL;

COMMIT;
