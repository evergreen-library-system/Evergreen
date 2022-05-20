BEGIN;

SELECT evergreen.upgrade_deps_block_check('1326', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.idl_field_doc', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.idl_field_doc',
        'Grid Config: admin.config.idl_field_doc',
        'cwst', 'label'
    )
);

COMMIT;
