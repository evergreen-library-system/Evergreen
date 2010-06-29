BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0323'); -- senator

-- In booking, elbow room defines:
--  a) how far in the future you must make a reservation on a given item if
--      that item will have to transit somewhere to fulfill the reservation.
--  b) how soon a reservation must be starting for the reserved item to
--      be op-captured by the checkin interface.

INSERT INTO config.org_unit_setting_type
    (name, label, description, datatype) VALUES (
        'circ.booking_reservation.default_elbow_room',
        oils_i18n_gettext(
            'circ.booking_reservation.default_elbow_room',
            'Booking: Elbow room',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.booking_reservation.default_elbow_room',
            'Elbow room specifies how far in the future you must make a reservation on an item if that item will have to transit to reach its pickup location.  It secondarily defines how soon a reservation on a given item must start before the check-in process will opportunistically capture it for the reservation shelf.',
            'coust',
            'label'
        ),
        'interval'
    );

INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.booking_reservation.default_elbow_room',
    '"1 day"'
);

COMMIT;
