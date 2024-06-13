BEGIN;

SELECT evergreen.upgrade_deps_block_check('1420', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.search.sort_order', 'gui', 'string',
    oils_i18n_gettext(
        'eg.search.sort_order',
        'Default sort order upon first opening a catalog search',
        'cwst', 'label'
    )
), 
(
    'eg.search.available_only', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.search.available_only',
        'Whether to search for only bibs with available items upon first opening a catalog search',
        'cwst', 'label'
    )
),
(
    'eg.search.group_formats', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.search.group_formats',
        'Whether to group formats/editions upon first opening a catalog search',
        'cwst', 'label'
    )
);


COMMIT;
