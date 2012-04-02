BEGIN;

SELECT evergreen.upgrade_deps_block_check('0700', :eg_version);

INSERT INTO config.internal_flag (name, value, enabled) VALUES (
    'serial.rematerialize_on_same_holding_code', NULL, FALSE
);

INSERT INTO config.org_unit_setting_type (
    name, label, grp, description, datatype
) VALUES (
    'serial.default_display_grouping',
    'Default display grouping for serials distributions presented in the OPAC.',
    'serial',
    'Default display grouping for serials distributions presented in the OPAC. This can be "enum" or "chron".',
    'string'
);

ALTER TABLE serial.distribution
    ADD COLUMN display_grouping TEXT NOT NULL DEFAULT 'chron'
        CHECK (display_grouping IN ('enum', 'chron'));

-- why didn't we just make one summary table in the first place?
CREATE VIEW serial.any_summary AS
    SELECT
        'basic' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.basic_summary
    UNION
    SELECT
        'index' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.index_summary
    UNION
    SELECT
        'supplement' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.supplement_summary ;


-- Given the IDs of two rows in actor.org_unit, *the second being an ancestor
-- of the first*, return in array form the path from the ancestor to the
-- descendant, with each point in the path being an org_unit ID.  This is
-- useful for sorting org_units by their position in a depth-first (display
-- order) representation of the tree.
--
-- This breaks with the precedent set by actor.org_unit_full_path() and others,
-- and gets the parameters "backwards," but otherwise this function would
-- not be very usable within json_query.
CREATE OR REPLACE FUNCTION actor.org_unit_simple_path(INT, INT)
RETURNS INT[] AS $$
    WITH RECURSIVE descendant_depth(id, path) AS (
        SELECT  aou.id,
                ARRAY[aou.id]
          FROM  actor.org_unit aou
                JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
          WHERE aou.id = $2
            UNION ALL
        SELECT  aou.id,
                dd.path || ARRAY[aou.id]
          FROM  actor.org_unit aou
                JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
                JOIN descendant_depth dd ON (dd.id = aou.parent_ou)
    ) SELECT dd.path
        FROM actor.org_unit aou
        JOIN descendant_depth dd USING (id)
        WHERE aou.id = $1 ORDER BY dd.path;
$$ LANGUAGE SQL STABLE;

CREATE TABLE serial.materialized_holding_code (
    id BIGSERIAL PRIMARY KEY,
    issuance INTEGER NOT NULL REFERENCES serial.issuance (id) ON DELETE CASCADE,
    subfield CHAR,
    value TEXT
);

CREATE OR REPLACE FUNCTION serial.materialize_holding_code() RETURNS TRIGGER
AS $func$ 
use strict;

use MARC::Field;
use JSON::XS;

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

CREATE INDEX assist_holdings_display
    ON serial.materialized_holding_code (issuance, subfield);

CREATE TRIGGER materialize_holding_code
    AFTER INSERT OR UPDATE ON serial.issuance
    FOR EACH ROW EXECUTE PROCEDURE serial.materialize_holding_code() ;

-- starting here, we materialize all existing holding codes.

UPDATE config.internal_flag
    SET enabled = TRUE
    WHERE name = 'serial.rematerialize_on_same_holding_code';

UPDATE serial.issuance SET holding_code = holding_code;

UPDATE config.internal_flag
    SET enabled = FALSE
    WHERE name = 'serial.rematerialize_on_same_holding_code';

-- finish holding code materialization process

-- fix up missing holding_code fields from serial.issuance
UPDATE serial.issuance siss
    SET holding_type = scap.type
    FROM serial.caption_and_pattern scap
    WHERE scap.id = siss.caption_and_pattern AND siss.holding_type IS NULL;

COMMIT;
