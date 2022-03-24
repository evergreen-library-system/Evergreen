BEGIN;

SELECT evergreen.upgrade_deps_block_check('1316', :eg_version);

INSERT INTO config.ui_staff_portal_page_entry
    (id, page_col, col_pos, entry_type, label, image_url, target_url, owner)
VALUES
    ( 1, 1, 0, 'header',        oils_i18n_gettext( 1, 'Circulation and Patrons', 'cusppe', 'label'), NULL, NULL, 1)
,   ( 2, 1, 1, 'menuitem',      oils_i18n_gettext( 2, 'Check Out Items', 'cusppe', 'label'), '/images/portal/forward.png', '/eg/staff/circ/patron/bcsearch', 1)
,   ( 3, 1, 2, 'menuitem',      oils_i18n_gettext( 3, 'Check In Items', 'cusppe', 'label'), '/images/portal/back.png', '/eg/staff/circ/checkin/index', 1)
,   ( 4, 1, 3, 'menuitem',      oils_i18n_gettext( 4, 'Search For Patron By Name', 'cusppe', 'label'), '/images/portal/retreivepatron.png', '/eg/staff/circ/patron/search', 1)
,   ( 5, 2, 0, 'header',        oils_i18n_gettext( 5, 'Item Search and Cataloging', 'cusppe', 'label'), NULL, NULL, 1)
,   ( 6, 2, 1, 'catalogsearch', oils_i18n_gettext( 6, 'Search Catalog', 'cusppe', 'label'), NULL, NULL, 1)
,   ( 7, 2, 2, 'menuitem',      oils_i18n_gettext( 7, 'Record Buckets', 'cusppe', 'label'), '/images/portal/bucket.png', '/eg/staff/cat/bucket/record/', 1)
,   ( 8, 2, 3, 'menuitem',      oils_i18n_gettext( 8, 'Item Buckets', 'cusppe', 'label'), '/images/portal/bucket.png', '/eg/staff/cat/bucket/copy/', 1)
,   ( 9, 3, 0, 'header',        oils_i18n_gettext( 9, 'Administration', 'cusppe', 'label'), NULL, NULL, 1)
,   (10, 3, 1, 'link',          oils_i18n_gettext(10, 'Evergreen Documentation', 'cusppe', 'label'), '/images/portal/helpdesk.png', 'https://docs.evergreen-ils.org', 1)
,   (11, 3, 2, 'menuitem',      oils_i18n_gettext(11, 'Workstation Administration', 'cusppe', 'label'), '/images/portal/helpdesk.png', '/eg/staff/admin/workstation/index', 1)
,   (12, 3, 3, 'menuitem',      oils_i18n_gettext(12, 'Reports', 'cusppe', 'label'), '/images/portal/reports.png', '/eg/staff/reporter/legacy/main', 1)
;

SELECT setval('config.ui_staff_portal_page_entry_id_seq', 100);


INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.ui_staff_portal_page_entry', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.ui_staff_portal_page_entry',
        'Grid Config: admin.config.ui_staff_portal_page_entry',
        'cwst', 'label'
    )
);

COMMIT;

