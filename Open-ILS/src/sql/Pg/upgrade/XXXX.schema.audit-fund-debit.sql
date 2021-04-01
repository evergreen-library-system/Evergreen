BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

SELECT auditor.create_auditor ( 'acq', 'fund_debit' );

COMMIT;

