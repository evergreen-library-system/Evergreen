BEGIN;
SELECT evergreen.upgrade_deps_block_check('1204', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 621, 'VIEW_BOOKING_RESOURCE_TYPE', oils_i18n_gettext(621,
    'View booking resource types', 'ppl', 'description')),
 ( 622, 'VIEW_BOOKING_RESOURCE', oils_i18n_gettext(622,
    'View booking resources', 'ppl', 'description'))
;

COMMIT;
