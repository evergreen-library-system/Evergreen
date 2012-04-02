BEGIN;

SELECT evergreen.upgrade_deps_block_check('0699', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, grp )
    VALUES (
        'ui.hide_copy_editor_fields',
        oils_i18n_gettext(
            'ui.hide_copy_editor_fields',
            'GUI: Hide these fields within the Item Attribute Editor',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.hide_copy_editor_fields',
            'This setting may be best maintained with the dedicated configuration'
            || ' interface within the Item Attribute Editor.  However, here it'
            || ' shows up as comma separated list of field identifiers to hide.',
            'coust',
            'description'
        ),
        'array',
        'gui'
    );


COMMIT;
