BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0117'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES 
( 'ui.circ_and_cat.notes.require_initials',
  oils_i18n_gettext('ui.staff.require_initials', 'GUI: Require staff initials for entry/edit of item/patron/penalty notes/messages.', 'coust', 'label'),
  oils_i18n_gettext('ui.staff.require_initials', 'Appends staff initials and edit date into note content.', 'coust', 'description'),
  'bool' );

COMMIT;
