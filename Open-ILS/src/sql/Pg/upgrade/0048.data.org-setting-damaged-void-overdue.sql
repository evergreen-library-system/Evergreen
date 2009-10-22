BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0048');

INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.damaged.void_ovedue',
        'Mark item damaged voids overdues',
        'When an item is marked damaged, overdue fines on the most recent circulation are voided.',
        'bool'
    );

COMMIT;
