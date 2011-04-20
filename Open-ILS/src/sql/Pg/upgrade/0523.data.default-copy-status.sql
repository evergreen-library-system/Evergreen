BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0523'); -- dbs

INSERT into config.org_unit_setting_type
( name, label, description, datatype, fm_class ) VALUES
( 'cat.default_copy_status_fast',
  oils_i18n_gettext( 'cat.default_copy_status_fast', 'Cataloging: Default copy status (fast add)', 'coust', 'label'),
  oils_i18n_gettext( 'cat.default_copy_status_fast', 'Default status when a copy is created using the "Fast Add" interface.', 'coust', 'description'),
  'link', 'ccs'
);

INSERT into config.org_unit_setting_type
( name, label, description, datatype, fm_class ) VALUES
( 'cat.default_copy_status_normal',
  oils_i18n_gettext( 'cat.default_copy_status_normal', 'Cataloging: Default copy status (normal)', 'coust', 'label'),
  oils_i18n_gettext( 'cat.default_copy_status_normal', 'Default status when a copy is created using the normal volume/copy creator interface.', 'coust', 'description'),
  'link', 'ccs'
);

COMMIT;
