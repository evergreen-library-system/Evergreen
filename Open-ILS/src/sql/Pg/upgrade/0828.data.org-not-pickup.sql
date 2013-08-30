BEGIN;

SELECT evergreen.upgrade_deps_block_check('0828', :eg_version);

INSERT into config.org_unit_setting_type 
    (name, grp, label, description, datatype)
VALUES ( 
    'opac.holds.org_unit_not_pickup_lib', 
    'opac',
    oils_i18n_gettext('opac.holds.org_unit_not_pickup_lib',
        'OPAC: Org Unit is not a hold pickup library',
        'coust', 'label'),
    oils_i18n_gettext('opac.holds.org_unit_not_pickup_lib',
        'If set, this org unit will not be offered to the patron as an '||
        'option for a hold pickup location.  This setting has no affect '||
        'on searching or hold targeting',
        'coust', 'description'),
    'bool'
);

COMMIT;

