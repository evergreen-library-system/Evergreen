BEGIN;

SELECT evergreen.upgrade_deps_block_check('1531', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype, fm_class)
VALUES
( 'opac.ecard_renewal_bypass_checks', 'opac',
    oils_i18n_gettext('opac.ecard_renewal_bypass_checks',
        'Bypass checks of eCard renewals',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_renewal_bypass_checks',
        'Allow bypassing certain checks for online card renewals; this is meant for cases where the an external system such as a discovery layer is hosting the renewal form and is assuming responsiblity for validating that the patron has requested it',
        'coust', 'description'),
    'bool', null)
;

COMMIT;
