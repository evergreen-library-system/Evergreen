BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0524'); -- phasefx

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'ui.unified_volume_copy_editor',
  oils_i18n_gettext( 'ui.unified_volume_copy_editor', 'GUI: Unified Volume/Item Creator/Editor', 'coust', 'label'),
  oils_i18n_gettext( 'ui.unified_volume_copy_editor', 'If true combines the Volume/Copy Creator and Item Attribute Editor in some instances.', 'coust', 'description'),
  'bool'
);

COMMIT;
