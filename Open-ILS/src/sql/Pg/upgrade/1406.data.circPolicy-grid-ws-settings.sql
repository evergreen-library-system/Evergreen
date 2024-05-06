BEGIN;

SELECT evergreen.upgrade_deps_block_check('1406', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label) 
VALUES (
    'eg.grid.admin.config.circ_matrix_matchpoint', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.circ_matrix_matchpoint',
        'Grid Config: admin.config.circ_matrix_matchpoint',
        'cwst', 'label'
    )
);

COMMIT;
