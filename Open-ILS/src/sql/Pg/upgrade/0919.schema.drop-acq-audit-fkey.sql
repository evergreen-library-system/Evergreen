BEGIN;

SELECT evergreen.upgrade_deps_block_check('0919', :eg_version);

ALTER TABLE acq.acq_lineitem_history DROP CONSTRAINT IF EXISTS acq_lineitem_history_queued_record_fkey;

COMMIT;
