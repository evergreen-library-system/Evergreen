BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'acq.fund.rollover_distrib_forms',
    oils_i18n_gettext(
        'acq.fund.rollover_distrib_forms',
        'Rollover Distribution Formulae Funds',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.fund.rollover_distrib_forms',
        'During fiscal rollover, update distribution formalae to use new funds',
        'coust',
        'description'
    ),
    'acq',
    'bool'
);

COMMIT;
