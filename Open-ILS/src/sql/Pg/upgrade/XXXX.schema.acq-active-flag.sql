BEGIN;

--SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

-- Add an active flag column

ALTER TABLE acq.funding_source ADD COLUMN active BOOL;

UPDATE acq.funding_source SET active = 't';

ALTER TABLE acq.funding_source ALTER COLUMN active SET DEFAULT TRUE;
ALTER TABLE acq.funding_source ALTER COLUMN active SET NOT NULL;

COMMIT;
