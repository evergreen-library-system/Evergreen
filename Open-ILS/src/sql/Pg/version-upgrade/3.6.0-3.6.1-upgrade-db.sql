--Upgrade Script for 3.6.0 to 3.6.1
\set eg_version '''3.6.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.6.1', :eg_version);

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



-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1242', :eg_version);

-- Long Overdue
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.longoverdue';

-- Lost
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.lost';

-- Claims Returned
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.claimsreturned';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
