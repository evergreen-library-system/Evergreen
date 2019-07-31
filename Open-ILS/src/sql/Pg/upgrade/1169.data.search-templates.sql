
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1169', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.search_templates', 'gui', 'object',
    oils_i18n_gettext(
        'eg.catalog.search_templates',
        'Staff Catalog Search Templates',
        'cwst', 'label'
    )
);

COMMIT;

