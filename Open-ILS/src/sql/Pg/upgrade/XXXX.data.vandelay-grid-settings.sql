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
    'eg.grid.cat.vandelay.queue.authority', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.authority',
        'Grid Config: Vandelay Authority Queue',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.match_set.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.match_set.list',
        'Grid Config: Vandelay Match Sets',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.match_set.quality', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.match_set.quality',
        'Grid Config: Vandelay Match Quality Metrics',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.items', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.items',
        'Grid Config: Vandelay Queue Import Items',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.list.bib', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.list.bib',
        'Grid Config: Vandelay Bib Queue List',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.bib.items', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.bib.items',
        'Grid Config: Vandelay Bib Items',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.vandelay.queue.list.auth', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.list.auth',
        'Grid Config: Vandelay Authority Queue List',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.vandelay.merge_profile', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.vandelay.merge_profile',
        'Grid Config: Vandelay Merge Profiles',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.vandelay.bib_attr_definition', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.vandelay.bib_attr_definition',
        'Grid Config: Vandelay Bib Record Attributes',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.vandelay.import_item_attr_definition', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.vandelay.import_item_attr_definition',
        'Grid Config: Vandelay Import Item Attributes',
        'cwst', 'label'
    )
);


COMMIT;


