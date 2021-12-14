BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version); -- jboyer /  / 

ALTER TABLE reporter.template_folder ADD COLUMN simple_reporter BOOLEAN DEFAULT FALSE;
ALTER TABLE reporter.report_folder ADD COLUMN simple_reporter BOOLEAN DEFAULT FALSE;
ALTER TABLE reporter.output_folder ADD COLUMN simple_reporter BOOLEAN DEFAULT FALSE;

DROP INDEX reporter.rpt_template_folder_once_idx;
DROP INDEX reporter.rpt_report_folder_once_idx;
DROP INDEX reporter.rpt_output_folder_once_idx;

CREATE UNIQUE INDEX rpt_template_folder_once_idx ON reporter.template_folder (name,owner,simple_reporter) WHERE parent IS NULL;
CREATE UNIQUE INDEX rpt_report_folder_once_idx ON reporter.report_folder (name,owner,simple_reporter) WHERE parent IS NULL;
CREATE UNIQUE INDEX rpt_output_folder_once_idx ON reporter.output_folder (name,owner,simple_reporter) WHERE parent IS NULL;

-- Private "transform" to allow for simple report permissions verification
CREATE OR REPLACE FUNCTION reporter.intersect_user_perm_ou(context_ou BIGINT, staff_id BIGINT, perm_code TEXT)
RETURNS BOOLEAN AS $$
  SELECT CASE WHEN context_ou IN (SELECT * FROM permission.usr_has_perm_at_all(staff_id::INT, perm_code)) THEN TRUE ELSE FALSE END;
$$ LANGUAGE SQL;

-- Hey committer, make sure this id is good to go and also in 950.data.seed-values.sql
INSERT INTO permission.perm_list (id, code, description) VALUES
 ( 636, 'RUN_SIMPLE_REPORTS', oils_i18n_gettext(636,
    'Build and run simple reports', 'ppl', 'description'));


INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.reporter.simple.reports', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.reporter.simple.reports',
        'Grid Config: eg.grid.reporter.simple.reports',
        'cwst', 'label'
    )
), (
    'eg.grid.reporter.simple.outputs', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.reporter.simple.outputs',
        'Grid Config: eg.grid.reporter.simple.outputs',
        'cwst', 'label'
    )
);

-- new view parallel to reporter.currently_running
-- and reporter.overdue_reports
CREATE OR REPLACE VIEW reporter.completed_reports AS
  SELECT s.id AS run,
         r.id AS report,
         t.id AS template,
         t.owner AS template_owner,
         r.owner AS report_owner,
         s.runner AS runner,
         t.folder AS template_folder,
         r.folder AS report_folder,
         s.folder AS output_folder,
         r.name AS report_name,
         t.name AS template_name,
         s.start_time,
         s.run_time,
         s.complete_time,
         s.error_code,
         s.error_text
  FROM reporter.schedule s
    JOIN reporter.report r ON r.id = s.report
    JOIN reporter.template t ON t.id = r.template
  WHERE s.complete_time IS NOT NULL;

COMMIT;

