BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0109'); --miker

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.booking_reservation.stop_circ',
    'Disallow circulation of items when they are on booking reserve and that reserve overlaps with the checkout period',
    'When true, items on booking reserve during the proposed checkout period will not be allowed to circulate unless overridden with the COPY_RESERVED.override permission.',
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.booking_reservation.default_elbow_room',
    'Default amount of time by which a circulation should be shortened to allow for booking reservation delivery',
    'When an item is on booking reserve, and that reservation overlaps with the proposed checkout period, and circulations have not been strictly disallowed on reserved items, Evergreen will attempt to adjust the due date of the circulation for this about of time before the beginning of the reservation period.  If this is not possible because the due date would end up in the past, the circulation is disallowed.',
    'interval'
);

COMMIT;

