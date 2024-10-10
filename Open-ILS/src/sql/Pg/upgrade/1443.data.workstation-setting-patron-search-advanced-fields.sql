BEGIN;

SELECT evergreen.upgrade_deps_block_check('1443', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.circ.patron.search.show_names',
    'gui',
    oils_i18n_gettext('eg.circ.patron.search.show_names',
        'Staff Client patron search: show name fields',
        'coust', 'label'),
    oils_i18n_gettext('eg.circ.patron.search.show_names',
        'Displays the name row of advanced patron search fields',
        'coust', 'description'),
    'bool'
);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.circ.patron.search.show_ids',
    'gui',
    oils_i18n_gettext('eg.circ.patron.search.show_ids',
        'Staff Client patron search: show ID fields',
        'coust', 'label'),
    oils_i18n_gettext('eg.circ.patron.search.show_ids',
        'Displays the ID row of advanced patron search fields',
        'coust', 'description'),
    'bool'
);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.circ.patron.search.show_address',
    'gui',
    oils_i18n_gettext('eg.circ.patron.search.show_address',
        'Staff Client patron search: show address fields',
        'coust', 'label'),
    oils_i18n_gettext('eg.circ.patron.search.show_address',
        'Displays the address row of advanced patron search fields',
        'coust', 'description'),
    'bool'
);

COMMIT;
