BEGIN;

SELECT evergreen.upgrade_deps_block_check('0710', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.could_be_serial_holding_code(TEXT) RETURNS BOOL AS $$
    use JSON::XS;
    use MARC::Field;

    eval {
        my $holding_code = (new JSON::XS)->decode(shift);
        new MARC::Field('999', @$holding_code);
    };
    return $@ ? 0 : 1;
$$ LANGUAGE PLPERLU;

-- This throws away data, but only data that causes breakage anyway.
UPDATE serial.issuance
    SET holding_code = NULL
    WHERE NOT could_be_serial_holding_code(holding_code);

ALTER TABLE serial.issuance
    DROP CONSTRAINT IF EXISTS issuance_holding_code_check;

ALTER TABLE serial.issuance
    ADD CHECK (holding_code IS NULL OR could_be_serial_holding_code(holding_code));

COMMIT;
