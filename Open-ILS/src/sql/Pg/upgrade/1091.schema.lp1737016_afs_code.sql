BEGIN;

SELECT evergreen.upgrade_deps_block_check('1091', :eg_version);

ALTER TABLE acq.funding_source DROP CONSTRAINT funding_source_code_key;
ALTER TABLE acq.funding_source ALTER COLUMN code SET NOT NULL;
ALTER TABLE acq.funding_source ADD CONSTRAINT funding_source_code_once_per_owner UNIQUE (code,owner);

COMMIT;
