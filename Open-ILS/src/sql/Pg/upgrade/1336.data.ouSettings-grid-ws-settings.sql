BEGIN;

SELECT evergreen.upgrade_deps_block_check('1336', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label) 
VALUES (
    'eg.grid.admin.actor.org_unit_settings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.actor.org_unit_settings',
        'Grid Config: admin.actor.org_unit_settings',
        'cwst', 'label'
    )
);

COMMIT;
