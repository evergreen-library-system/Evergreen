-- Drop the never-used column item_count from acq.lineitem.
-- Drop it also from the associated history table, and rebuild
-- the function that maintains it.  Finally, rebuild the
-- associated lifecycle view.  

-- Apply to trunk only; this column never existed in 2.0.

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0417'); -- Scott McKellar

-- Have to drop the view first, because it's a dependent
DROP VIEW IF EXISTS acq.acq_lineitem_lifecycle;

ALTER TABLE acq.lineitem DROP COLUMN item_count;

ALTER TABLE acq.acq_lineitem_history DROP COLUMN item_count;

SELECT acq.create_acq_func( 'acq', 'lineitem' );

SELECT acq.create_acq_lifecycle( 'acq', 'lineitem' );

COMMIT;
