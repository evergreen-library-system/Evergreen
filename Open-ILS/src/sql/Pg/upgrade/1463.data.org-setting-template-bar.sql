BEGIN;

SELECT evergreen.upgrade_deps_block_check('1463', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'gui',
    'ui.cat.volume_copy_editor.template_bar.show_save_template', 'bool',
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.template_bar.show_save_template',
        'Show "Save Template" in Holdings Editor',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.template_bar.show_save_template',
        'Displays the "Save Template" button for the template bar in the Volume/Copy/Holdings Editor. By default, this is only displayed when working with templates from the Admin interface.',
        'coust',
        'description'
    )
);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'gui',
    'ui.cat.volume_copy_editor.hide_template_bar', 'bool',
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.hide_template_bar',
        'Hide the entire template bar in Holdings Editor',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.hide_template_bar',
        'Hides the template bar in the Volume/Copy/Holdings Editor. By default, the template bar is displayed in this interface.',
        'coust',
        'description'
    )
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.volcopy.template_grid', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.cat.volcopy.template_grid',
        'Holdings Template Grid Settings',
        'cwst', 'label'
    )
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.holdings.copy_tags.tag_map_list', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.holdings.copy_tags.tag_map_list',
        'Copy Tag Maps Template Grid Settings',
        'cwst', 'label'
    )
);

COMMIT;
