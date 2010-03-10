
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0184'); -- miker

CREATE OR REPLACE FUNCTION vandelay.add_field ( incumbent_xml TEXT, incoming_xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML;

    my $incumbent_xml = shift;
    my $incoming_xml = shift;
    my $field_spec = shift;
    $field_spec =~ s/\s+//g;

    my $incumbent_r = MARC::Record->new_from_xml( $incumbent_xml );
    my $incoming_r = MARC::Record->new_from_xml( $incoming_xml );

    return $incumbent_xml unless ($incumbent_r && $incoming_r);

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        if ($f =~ /^(.{3})(.*)$/) {
            $fields{$1} = [ split('', $2) ];
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}} ) {
            for my $from_field ($incoming_r->field( $f )) {
                for my $to_field ($incumbent_r->field( $f )) {
                    my @new_sf = map { ($_ => $from_field->subfield($_)) } @{$fields{$f}};
                    $to_field->add_subfields( @new_sf );
                }
            }
        } else {
            my @new_fields = map { $_->clone } $incoming_r->field( $f );
            $incumbent_r->insert_fields_ordered( @new_fields );
        }
    }

    $incumbent_xml = $incumbent_r->as_xml_record;
    $incumbent_xml =~ s/^<\?.+?\?>$//mo;
    $incumbent_xml =~ s/\n//sgo;
    $incumbent_xml =~ s/>\s+</></sgo;

    return $incumbent_xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.strip_field ( xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML;

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    $field_spec =~ s/\s+//g;

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        if ($f =~ /^(.{3})(.*)$/) {
            $fields{$1} = [ split('', $2) ];
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}} ) {
            $_->delete_subfield(code => $fields{$f}) for ($r->field( $f ));
        } else {
            $r->delete_field( $_ ) for ( $r->field( $f ) );
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.replace_field ( incumbent_xml TEXT, incoming_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( vandelay.strip_field( $1, $3), $2, $3 );
$_$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.preserve_field ( incumbent_xml TEXT, incoming_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( vandelay.strip_field( $2, $3), $1, $3 );
$_$ LANGUAGE SQL;

COMMIT;
