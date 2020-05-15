BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.authority.browse', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.cat.authority.browse',
    'Grid Config: eg.grid.cat.authority.browse',
    'cwst', 'label')
), (
    'eg.grid.cat.authority.manage.bibs', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.cat.authority.manage.bibs',
    'Grid Config: eg.grid.cat.authority.manage.bibs',
    'cwst', 'label')
);

COMMIT;
