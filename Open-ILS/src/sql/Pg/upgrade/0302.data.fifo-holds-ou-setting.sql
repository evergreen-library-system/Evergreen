BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0302'); --miker

INSERT INTO config.org_unit_setting_type (name,label,description,datatype)
    VALUES ('circ.holds_fifo', 'Holds: FIFO', 'Force holds to a more strict First-In, First-Out capture', 'bool' );

COMMIT;

