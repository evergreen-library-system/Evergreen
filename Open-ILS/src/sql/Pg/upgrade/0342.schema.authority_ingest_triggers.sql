-- Enable automated ingest of authority records; just insert the row into
-- authority.record_entry and authority.full_rec will automatically be populated
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0342'); -- dbs 

CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( marc, authority.generate_overlay_template( $1 ) )
      WHERE id = $2;
    SELECT $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT) RETURNS SETOF BIGINT AS $func$
    SELECT authority.propagate_changes( authority, bib ) FROM authority.bib_linking WHERE authority = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( TEXT ) RETURNS SETOF authority.full_rec AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');

my $xml = shift;
my $r = MARC::Record->new_from_xml( $xml );

return_next( { tag => 'LDR', value => $r->leader } );

for my $f ( $r->fields ) {
    if ($f->is_control_field) {
        return_next({ tag => $f->tag, value => $f->data });
    } else {
        for my $s ($f->subfields) {
            return_next({
                tag      => $f->tag,
                ind1     => $f->indicator(1),
                ind2     => $f->indicator(2),
                subfield => $s->[0],
                value    => $s->[1]
            });

        }
    }
}

return undef;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( rid BIGINT ) RETURNS SETOF authority.full_rec AS $func$
DECLARE
    auth    authority.record_entry%ROWTYPE;
    output    authority.full_rec%ROWTYPE;
    field    RECORD;
BEGIN
    SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

    FOR field IN SELECT * FROM authority.flatten_marc( auth.marc ) LOOP
        output.record := rid;
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        IF field.subfield IS NOT NULL THEN
            output.value := naco_normalize(field.value, field.subfield);
        ELSE
            output.value := field.value;
        END IF;

        CONTINUE WHEN output.value IS NULL;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-- authority.rec_descriptor appears to be unused currently
CREATE OR REPLACE FUNCTION authority.reingest_authority_rec_descriptor( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.rec_descriptor WHERE record = auth_id;
--    INSERT INTO authority.rec_descriptor (record, record_status, char_encoding)
--        SELECT  auth_id, ;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.reingest_authority_full_rec( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.full_rec WHERE record = auth_id;
    INSERT INTO authority.full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM authority.flatten_marc( auth_id );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- AFTER UPDATE OR INSERT trigger for authority.record_entry
CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
          -- Should remove matching $0 from controlled fields at the same time?
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(NEW.id);
-- authority.rec_descriptor is not currently used
--        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
--        IF NOT FOUND THEN
--            PERFORM authority.reingest_authority_rec_descriptor(NEW.id);
--        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
