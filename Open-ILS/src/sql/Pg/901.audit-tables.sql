BEGIN;

SELECT auditor.create_auditor ( 'actor', 'usr' );
SELECT auditor.create_auditor ( 'actor', 'usr_address' );
SELECT auditor.create_auditor ( 'actor', 'org_unit' );
SELECT auditor.create_auditor ( 'biblio', 'record_entry' );
SELECT auditor.create_auditor ( 'asset', 'call_number' );
SELECT auditor.create_auditor ( 'asset', 'copy' );

COMMIT;

