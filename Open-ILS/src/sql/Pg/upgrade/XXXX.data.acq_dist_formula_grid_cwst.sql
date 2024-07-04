BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.distribution_formula', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.distribution_formula',
        'Grid Config: admin.acq.distribution_formula',
        'cwst', 'label'
    )
);

COMMIT;
