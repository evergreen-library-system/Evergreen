BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0321');

-- Function to generate an ephemeral overlay template from an authority record
CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT, BIGINT ) RETURNS TEXT AS $func$

    use MARC::Record;
    use MARC::File::XML;

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return undef unless ($r);

    my $id = shift() || $r->subfield( '901' => 'c' );
    $id =~ s/^\s*(?:\([^)]+\))?\s*(.+)\s*?$/$1/;
    return undef unless ($id); # We need an ID!

    my $tmpl = MARC::Record->new();

    my @rule_fields;
    for my $field ( $r->field( '1..' ) ) { # Get main entry fields from the authority record

        my $tag = $field->tag;
        my $i1 = $field->indicator(1);
        my $i2 = $field->indicator(2);
        my $sf = join '', map { $_->[0] } $field->subfields;
        my @data = map { @$_ } $field->subfields;

        my @replace_them;

        # Map the authority field to bib fields it can control.
        if ($tag >= 100 and $tag <= 111) {       # names
            @replace_them = map { $tag + $_ } (0, 300, 500, 600, 700);
        } elsif ($tag eq '130') {                # uniform title
            @replace_them = qw/130 240 440 730 830/;
        } elsif ($tag >= 150 and $tag <= 155) {  # subjects
            @replace_them = ($tag + 500);
        } elsif ($tag >= 180 and $tag <= 185) {  # floating subdivisions
            @replace_them = qw/100 400 600 700 800 110 410 610 710 810 111 411 611 711 811 130 240 440 730 830 650 651 655/;
        } else {
            next;
        }

        # Dummy up the bib-side data
        $tmpl->append_fields(
            map {
                MARC::Field->new( $_, $i1, $i2, @data )
            } @replace_them
        );

        # Construct some 'replace' rules
        push @rule_fields, map { $_ . $sf . '[0~\)' .$id . '$]' } @replace_them;
    }

    # Insert the replace rules into the template
    $tmpl->append_fields(
        MARC::Field->new( '905' => ' ' => ' ' => 'r' => join(',', @rule_fields ) )
    );

    $xml = $tmpl->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;

    # Leave formatting intact for now
    #$xml =~ s/\n//sgo;
    #$xml =~ s/>\s+</></sgo;

    return $xml;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( BIGINT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( marc, id ) FROM authority.record_entry WHERE id = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( $1, NULL );
$func$ LANGUAGE SQL;


COMMIT;

