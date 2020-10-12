BEGIN;

SELECT evergreen.upgrade_deps_block_check('1241', :eg_version);

SET CONSTRAINTS ALL IMMEDIATE; -- to address "pending trigger events" error

-- Dedupe the table before applying the script.  Preserve the original to allow the admin to delete it manually later.
CREATE TABLE reporter.schedule_original (LIKE reporter.schedule);
INSERT INTO reporter.schedule_original SELECT * FROM reporter.schedule;
TRUNCATE reporter.schedule;
INSERT INTO reporter.schedule (SELECT DISTINCT ON (report, folder, runner, run_time) id, report, folder, runner, run_time, start_time, complete_time, email, excel_format, html_format, csv_format, chart_pie, chart_bar, chart_line, error_code, error_text FROM reporter.schedule_original);
\qecho NOTE: This has created a backup of the original reporter.schedule
\qecho table, named reporter.schedule_original.  Once you are sure that everything
\qecho works as expected, you can delete that table by issuing the following:
\qecho
\qecho  'DROP TABLE reporter.schedule_original;'
\qecho

-- Explicitly supply the name because it is referenced in clark-kent.pl
CREATE UNIQUE INDEX rpt_sched_recurrence_once_idx ON reporter.schedule (report,folder,runner,run_time,COALESCE(email,''));

COMMIT;

