BEGIN;

SELECT evergreen.upgrade_deps_block_check('1241', :eg_version);

-- Explicitly supply the name because it is referenced in clark-kent.pl
CREATE UNIQUE INDEX rpt_sched_recurrence_once_idx ON reporter.schedule (report,folder,runner,run_time,email);

COMMIT;

