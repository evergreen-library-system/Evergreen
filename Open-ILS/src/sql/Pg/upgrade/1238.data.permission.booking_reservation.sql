BEGIN;

SELECT evergreen.upgrade_deps_block_check('1238', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 625, 'VIEW_BOOKING_RESERVATION', oils_i18n_gettext(625,
    'View booking reservations', 'ppl', 'description')),
 ( 626, 'VIEW_BOOKING_RESERVATION_ATTR_MAP', oils_i18n_gettext(626,
    'View booking reservation attribute maps', 'ppl', 'description'))
;

COMMIT;
