BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0232'); -- Scott McKellar

SELECT auditor.create_auditor ( 'acq', 'invoice' );

SELECT auditor.create_auditor ( 'acq', 'invoice_item' );

SELECT auditor.create_auditor ( 'acq', 'invoice_entry' );

COMMIT;
