BEGIN;

SELECT evergreen.upgrade_deps_block_check('0840', :eg_version);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.conify.config.circ_matrix_matchpoint',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.conify.config.circ_matrix_matchpoint',
        'Circulation Policy Configuration',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.conify.config.circ_matrix_matchpoint',
        'Circulation Policy Configuration Column Settings',
        'cust',
        'description'
    ),
    'string'
);

COMMIT;
