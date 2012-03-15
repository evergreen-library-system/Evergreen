BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

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

-- DELETE FROM actor.org_unit_setting WHERE name = 'ui.hide_copy_editor_fields'; DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'ui.hide_copy_editor_fields'; DELETE FROM config.org_unit_setting_type WHERE name = 'ui.hide_copy_editor_fields'; DELETE FROM config.upgrade_log WHERE version = 'XXXX';

COMMIT;
