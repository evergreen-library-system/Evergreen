BEGIN;

-- Add Stackmap library settings

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.stackmap_enable',
    'opac',
    oils_i18n_gettext('opac.stackmap_enable',
    'Stackmap: Enable',
    'coust', 'label'),
    oils_i18n_gettext('opac.stackmap_enable',
    'Enable Stackmap in the OPAC. Default is false.',
    'coust', 'description'),
    'bool'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.stackmap_identifier',
    'opac',
    oils_i18n_gettext('opac.stackmap_identifier',
    'Stackmap: Identifier',
    'coust', 'label'),
    oils_i18n_gettext('opac.stackmap_identifier',
    'Account code provided by Stackmap. (Example: pines-evergreen)',
    'coust', 'description'),
    'string'
);

COMMIT;
