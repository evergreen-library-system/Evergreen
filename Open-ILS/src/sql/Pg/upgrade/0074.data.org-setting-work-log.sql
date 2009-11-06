BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0074'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES
    ( 'ui.admin.work_log.max_entries',
        oils_i18n_gettext('ui.admin.work_log.max_entries', 'GUI: Work Log: Maximum Actions Logged', 'coust', 'label'),
        oils_i18n_gettext('ui.admin.work_log.max_entries', 'Maximum entries for "Most Recent Staff Actions" section of the Work Log interface.', 'coust', 'description'),
      'interval' ),

    ( 'ui.admin.patron_log.max_entries',
        oils_i18n_gettext('ui.admin.patron_log.max_entries', 'GUI: Work Log: Maximum Patrons Logged', 'coust', 'label'),
        oils_i18n_gettext('ui.admin.patron_log.max_entries', 'Maximum entries for "Most Recently Affected Patrons..." section of the Work Log interface.', 'coust', 'description'),
      'interval' )
;

COMMIT;
