BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.reporter.full.outputs.pending', 'gui', 'object', 
    oils_i18n_gettext( 'eg.grid.reporter.full.outputs.pending', 'Pending report output grid settings', 'cwst', 'label')
), (
    'eg.grid.reporter.full.outputs.complete', 'gui', 'object', 
    oils_i18n_gettext( 'eg.grid.reporter.full.outputs.complete', 'Completed report output grid settings', 'cwst', 'label')
), (
    'eg.grid.reporter.full.templates', 'gui', 'object', 
    oils_i18n_gettext( 'eg.grid.reporter.full.templates', 'Report template grid settings', 'cwst', 'label')
), (
    'eg.grid.reporter.full.reports', 'gui', 'object', 
    oils_i18n_gettext( 'eg.grid.reporter.full.reports', 'Report definition grid settings', 'cwst', 'label')
);

UPDATE  config.ui_staff_portal_page_entry
  SET   target_url = '/eg2/staff/reporter/full'
  WHERE id = 12
        AND entry_type = 'menuitem'
        AND target_url = '/eg/staff/reporter/legacy/main'
;

COMMIT;
