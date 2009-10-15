BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0036'); -- miker

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( rid BIGINT ) RETURNS SETOF metabib.full_rec AS $func$
DECLARE
	bib	biblio.record_entry%ROWTYPE;
	output	metabib.full_rec%ROWTYPE;
	field	RECORD;
BEGIN
	SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

	FOR field IN SELECT * FROM biblio.flatten_marc( bib.marc ) LOOP
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

		RETURN NEXT output;
	END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( TEXT ) RETURNS SETOF metabib.full_rec AS $func$

use MARC::Record;
use MARC::File::XML;

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

			if ( $f->tag eq '245' and $s->[0] eq 'a' ) {
				my $trim = $f->indicator(2) || 0;
				return_next({
					tag      => 'tnf',
					ind1     => $f->indicator(1),
					ind2     => $f->indicator(2),
					subfield => 'a',
					value    => substr( $s->[1], $trim )
				});
			}
		}
	}
}

return undef;

$func$ LANGUAGE PLPERLU;

COMMIT;
