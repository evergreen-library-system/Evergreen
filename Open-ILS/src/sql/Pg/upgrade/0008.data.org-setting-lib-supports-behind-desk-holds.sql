BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0008');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.behind_desk_pickup_supported',
    'Holds: Behind Desk Pickup Supported',
    'If a branch supports both a public holds shelf and behind-the-desk pickups, set this value to true.  This gives the patron the option to enable behind-the-desk pickups for their holds',
    'bool'
);

COMMIT;

