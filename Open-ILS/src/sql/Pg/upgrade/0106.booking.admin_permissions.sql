BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0106'); -- senator

INSERT INTO permission.perm_list (id, code, description) VALUES
    (352, 'ADMIN_BOOKING_RESOURCE', oils_i18n_gettext(352, 'Enables the user to create/update/delete booking resources', 'ppl', 'description')),
    (353, 'ADMIN_BOOKING_RESOURCE_TYPE', oils_i18n_gettext(353, 'Enables the user to create/update/delete booking resource types', 'ppl', 'description')),
    (354, 'ADMIN_BOOKING_RESOURCE_ATTR', oils_i18n_gettext(354, 'Enables the user to create/update/delete booking resource attributes', 'ppl', 'description')),
    (355, 'ADMIN_BOOKING_RESOURCE_ATTR_MAP', oils_i18n_gettext(355, 'Enables the user to create/update/delete booking resource attribute maps', 'ppl', 'description')),
    (356, 'ADMIN_BOOKING_RESOURCE_ATTR_VALUE', oils_i18n_gettext(356, 'Enables the user to create/update/delete booking resource attribute values', 'ppl', 'description')),
    (357, 'ADMIN_BOOKING_RESERVATION', oils_i18n_gettext(357, 'Enables the user to create/update/delete booking reservations', 'ppl', 'description')),
    (358, 'ADMIN_BOOKING_RESERVATION_ATTR_VALUE_MAP', oils_i18n_gettext(358, 'Enables the user to create/update/delete booking reservation attribute value maps', 'ppl', 'description'))
;

COMMIT;
