BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0050');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.canceled.display_count',
        'Holds: Canceled holds display count',
        'How many canceled holds to show in patron holds interfaces',
        'integer'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.canceled.display_age',
        'Holds: Canceled holds display age',
        'Show all canceled holds that were canceled within this amount of time',
        'interval'
    );

COMMIT;
