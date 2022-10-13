BEGIN;

SELECT evergreen.upgrade_deps_block_check('1337', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'cat.require_call_number_labels', 'cat',
  oils_i18n_gettext('cat.require_call_number_labels',
    'Require call number labels in Copy Editor',
    'coust', 'label'),
  oils_i18n_gettext('cat.require_call_number_labels',
    'Define whether Copy Editor requires Call Number labels',
    'coust', 'description'),
  'bool', null);

INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES
  (1, 'cat.require_call_number_labels', 'true');

COMMIT;
