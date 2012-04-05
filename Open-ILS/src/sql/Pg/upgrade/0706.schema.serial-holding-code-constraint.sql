BEGIN;

SELECT evergreen.upgrade_deps_block_check('0706', :eg_version);

-- This throws away data, but only data that causes breakage anyway.
UPDATE serial.issuance SET holding_code = NULL WHERE NOT is_json(holding_code);

-- If we don't do this, we have unprocessed triggers and we can't alter the table
SET CONSTRAINTS serial.issuance_caption_and_pattern_fkey IMMEDIATE;

ALTER TABLE serial.issuance ADD CHECK (holding_code IS NULL OR is_json(holding_code));

-- For the sake of completeness if these sneaked through
ALTER TABLE serial.materialized_holding_code DROP COLUMN IF EXISTS holding_type;
ALTER TABLE serial.materialized_holding_code DROP COLUMN IF EXISTS ind1;
ALTER TABLE serial.materialized_holding_code DROP COLUMN IF EXISTS ind2;

CREATE OR REPLACE FUNCTION serial.materialize_holding_code() RETURNS TRIGGER
AS $func$ 
use strict;

use MARC::Field;
use JSON::XS;

if (not defined $_TD->{new}{holding_code}) {
    elog(WARNING, 'NULL in "holding_code" column of serial.issuance allowed for now, but may not be useful');
    return;
}

# Do nothing if holding_code has not changed...

if ($_TD->{new}{holding_code} eq $_TD->{old}{holding_code}) {
    # ... unless the following internal flag is set.

    my $flag_rv = spi_exec_query(q{
        SELECT * FROM config.internal_flag
        WHERE name = 'serial.rematerialize_on_same_holding_code' AND enabled
    }, 1);
    return unless $flag_rv->{processed};
}


my $holding_code = (new JSON::XS)->decode($_TD->{new}{holding_code});

my $field = new MARC::Field('999', @$holding_code); # tag doesnt matter

my $dstmt = spi_prepare(
    'DELETE FROM serial.materialized_holding_code WHERE issuance = $1',
    'INT'
);
spi_exec_prepared($dstmt, $_TD->{new}{id});

my $istmt = spi_prepare(
    q{
        INSERT INTO serial.materialized_holding_code (
            issuance, subfield, value
        ) VALUES ($1, $2, $3)
    }, qw{INT CHAR TEXT}
);

foreach ($field->subfields) {
    spi_exec_prepared(
        $istmt,
        $_TD->{new}{id},
        $_->[0],
        $_->[1]
    );
}

return;

$func$ LANGUAGE 'plperlu';

COMMIT;
