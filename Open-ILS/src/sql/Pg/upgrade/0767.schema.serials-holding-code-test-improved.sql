BEGIN;

SELECT evergreen.upgrade_deps_block_check('0767', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.could_be_serial_holding_code(TEXT) RETURNS BOOL AS $$
    use JSON::XS;
    use MARC::Field;

    eval {
        my $holding_code = (new JSON::XS)->decode(shift);
        new MARC::Field('999', @$holding_code);
    };
    return 0 if $@; 
    # verify that subfield labels are exactly one character long
    foreach (keys %{ { @$holding_code } }) {
        return 0 if length($_) != 1;
    }
    return 1;
$$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION evergreen.could_be_serial_holding_code(TEXT) IS
    'Return true if parameter is valid JSON representing an array that at minimu
m doesn''t make MARC::Field balk and only has subfield labels exactly one character long.  Otherwise false.';


-- This UPDATE throws away data, but only bad data that makes things break
-- anyway.
UPDATE serial.issuance
    SET holding_code = NULL
    WHERE NOT could_be_serial_holding_code(holding_code);

ALTER TABLE serial.issuance
    DROP CONSTRAINT IF EXISTS issuance_holding_code_check;

ALTER TABLE serial.issuance
    ADD CHECK (holding_code IS NULL OR could_be_serial_holding_code(holding_code));

COMMIT;
