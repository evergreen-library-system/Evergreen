BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0397');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES (
        'opac.fully_compressed_serial_holdings',
        'OPAC: Use fully compressed serial holdings',
        'Show fully compressed serial holdings for all libraries at and below
        the current context unit',
        'bool'
    );

COMMIT;
