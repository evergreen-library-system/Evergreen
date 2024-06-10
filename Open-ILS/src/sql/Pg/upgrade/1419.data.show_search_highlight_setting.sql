BEGIN;

SELECT evergreen.upgrade_deps_block_check('1419', :eg_version);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.show_search_highlight',
    'gui',
    TRUE,
    oils_i18n_gettext(
        'ui.show_search_highlight',
        'Search Highlight',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.show_search_highlight',
        'A toggle deciding whether to highlight strings in a keyword search result matching the searched term(s)',
        'cust',
        'description'
    ),
    'bool'
);

COMMIT;