BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.server.actor.org_unit_proximity_adjustment', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.actor.org_unit_proximity_adjustment',
        'Grid Config: eg.grid.admin.server.actor.org_unit_proximity_adjustment',
        'cwst', 'label'
    )
);

COMMIT;
