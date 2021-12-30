BEGIN;

SELECT evergreen.upgrade_deps_block_check('1281', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.cat.volcopy.defaults', 'cat', 'object',
    oils_i18n_gettext(
        'eg.cat.volcopy.defaults',
        'Holdings Editor Default Values and Visibility',
        'cwst', 'label'
    )
);

COMMIT;
