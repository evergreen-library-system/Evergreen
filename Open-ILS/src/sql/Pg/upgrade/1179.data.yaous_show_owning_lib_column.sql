BEGIN;

SELECT evergreen.upgrade_deps_block_check('1179', :eg_version);

INSERT INTO config.org_unit_setting_type 
    (grp, name, datatype, label, description)
VALUES (
    'opac',
    'opac.show_owning_lib_column', 'bool',
    oils_i18n_gettext(
        'opac.show_owning_lib_column',
        'Show Owning Lib in Items Out',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.show_owning_lib_column',
'If enabled, the Owning Lib will be shown in the Items Out display.' ||
' This may assist in requesting additional renewals',
        'coust',
        'description'
    )
);

COMMIT;
