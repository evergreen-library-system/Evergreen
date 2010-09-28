BEGIN;

-- Turn an int into a bigint in acq.acq_lineitem_history, following up on
-- a similar change to acq.lineitem

INSERT INTO config.upgrade_log (version) VALUES ('0422'); -- Scott McKellar

DROP VIEW IF EXISTS acq.acq_lineitem_lifecycle;

ALTER TABLE acq.acq_lineitem_history
	ALTER COLUMN eg_bib_id SET DATA TYPE bigint;

SELECT acq.create_acq_lifecycle( 'acq', 'lineitem' );

COMMIT;
