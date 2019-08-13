BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label) 
VALUES (
    'eg.grid.asset.ouSettings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.asset.ouSettings',
        'Grid Config: asset.ouSettings',
        'cwst', 'label'
    )
);

COMMIT;