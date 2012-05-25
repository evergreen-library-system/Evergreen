BEGIN;

SELECT evergreen.upgrade_deps_block_check('0713', :eg_version);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.circ.hold_pull_list',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.circ.hold_pull_list',
        'Hold Pull List',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.circ.hold_pull_list',
        'Hold Pull List Saved Column Settings',
        'cust',
        'description'
    ),
    'string'
);

COMMIT;
