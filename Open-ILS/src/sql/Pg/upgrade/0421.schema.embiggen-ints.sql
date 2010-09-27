-- 1. Turn some ints into bigints.

-- 2. Rename a constraint for consistency and accuracy (currently it may
-- have either of two different names).

\qecho One of the following DROPs will fail, so we do them
\qecho both outside of a transaction.  Ignore the failure.

ALTER TABLE booking.resource_type
	DROP CONSTRAINT brt_name_or_record_once_per_owner;

ALTER TABLE booking.resource_type
	DROP CONSTRAINT brt_name_once_per_owner;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0421'); -- Scott McKellar

ALTER TABLE booking.resource_type
	ALTER COLUMN record SET DATA TYPE bigint,
	ADD CONSTRAINT brt_name_and_record_once_per_owner UNIQUE(owner, name, record);

ALTER TABLE container.biblio_record_entry_bucket_item
	ALTER COLUMN target_biblio_record_entry SET DATA TYPE bigint;

-- Before we can embiggen the next one, we must drop a view
-- that depends on it (and recreate it later)

DROP VIEW IF EXISTS acq.acq_lineitem_lifecycle;

ALTER TABLE acq.lineitem
	ALTER COLUMN eg_bib_id SET DATA TYPE bigint;

-- Recreate the view

SELECT acq.create_acq_lifecycle( 'acq', 'lineitem' );

ALTER TABLE vandelay.queued_bib_record
	ALTER COLUMN imported_as SET DATA TYPE bigint;

ALTER TABLE action.hold_copy_map
	ALTER COLUMN id SET DATA TYPE bigint;

COMMIT;
