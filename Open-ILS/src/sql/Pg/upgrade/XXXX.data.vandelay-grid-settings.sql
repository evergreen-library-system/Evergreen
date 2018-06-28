BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.vandelay.queue.bib', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.bib',
        'Grid Config: Vandelay Bib Queue',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.auth', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.auth',
        'Grid Config: Vandelay Authority Queue',
        'cwst', 'label'
    )
), (
    'cat.vandelay.match_set.list', 'gui', 'object',
    oils_i18n_gettext(
        'cat.vandelay.match_set.list',
        'Grid Config: Vandelay Match Sets',
        'cwst', 'label'
    )
), (
    'staff.cat.vandelay.match_set.quality', 'gui', 'object',
    oils_i18n_gettext(
        'staff.cat.vandelay.match_set.quality',
        'Grid Config: Vandelay Match Quality Metrics',
        'cwst', 'label'
    )
), (
    'cat.vandelay.queue.items', 'gui', 'object',
    oils_i18n_gettext(
        'cat.vandelay.queue.items',
        'Grid Config: Vandelay Queue Import Items',
        'cwst', 'label'
    )
), (
    'cat.vandelay.queue.list.bib', 'gui', 'object',
    oils_i18n_gettext(
        'cat.vandelay.queue.list.bib',
        'Grid Config: Vandelay Bib Queue List',
        'cwst', 'label'
    )
), (
    'cat.vandelay.queue.bib.items', 'gui', 'object',
    oils_i18n_gettext(
        'cat.vandelay.queue.bib.items',
        'Grid Config: Vandelay Bib Items',
        'cwst', 'label'
    )
), (
    'cat.vandelay.queue.list.auth', 'gui', 'object',
    oils_i18n_gettext(
        'cat.vandelay.queue.list.auth',
        'Grid Config: Vandelay Authority Queue List',
        'cwst', 'label'
    )
);

COMMIT;


