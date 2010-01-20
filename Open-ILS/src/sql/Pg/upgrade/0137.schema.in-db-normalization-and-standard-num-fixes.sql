
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0137'); -- miker

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( rid BIGINT ) RETURNS SETOF metabib.full_rec AS $func$
DECLARE
    bib biblio.record_entry%ROWTYPE;
    output  metabib.full_rec%ROWTYPE;
    field   RECORD;
BEGIN
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    FOR field IN SELECT * FROM biblio.flatten_marc( bib.marc ) LOOP
        output.record := rid;
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        IF field.subfield IS NOT NULL AND field.tag NOT IN ('020','022','024') THEN -- exclude standard numbers and control fields
            output.value := naco_normalize(field.value, field.subfield);
        ELSE
            output.value := field.value;
        END IF;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$
    use Unicode::Normalize;
    use Encode;

    my $txt = lc(encode_utf8(shift));
    my $sf = shift;

    $txt = NFD($txt);
    $txt =~ s/\pM+//go; # Remove diacritics

    $txt =~ s/\xE6/AE/go;   # Convert ae digraph
    $txt =~ s/\x{153}/OE/go;# Convert oe digraph
    $txt =~ s/\xFE/TH/go;   # Convert Icelandic thorn

    $txt =~ tr/\x{2070}\x{2071}\x{2072}\x{2073}\x{2074}\x{2075}\x{2076}\x{2077}\x{2078}\x{2079}\x{207A}\x{207B}/0123456789+-/;# Convert superscript numbers
    $txt =~ tr/\x{2080}\x{2081}\x{2082}\x{2083}\x{2084}\x{2085}\x{2086}\x{2087}\x{2088}\x{2089}\x{208A}\x{208B}/0123456889+-/;# Convert subscript numbers

    $txt =~ tr/\x{0251}\x{03B1}\x{03B2}\x{0262}\x{03B3}/AABGG/;     # Convert Latin and Greek
    $txt =~ tr/\x{2113}\xF0\!\"\(\)\-\{\}\<\>\;\:\.\?\xA1\xBF\/\\\@\*\%\=\xB1\+\xAE\xA9\x{2117}\$\xA3\x{FFE1}\xB0\^\_\~\`/LD /; # Convert Misc
    $txt =~ tr/\'\[\]\|//d;                         # Remove Misc

    if ($sf && $sf =~ /^a/o) {
        my $commapos = index($txt,',');
        if ($commapos > -1) {
            if ($commapos != length($txt) - 1) {
                my @list = split /,/, $txt;
                my $first = shift @list;
                $txt = $first . ',' . join(' ', @list);
            } else {
                $txt =~ s/,/ /go;
            }
        }
    } else {
        $txt =~ s/,/ /go;
    }

    $txt =~ s/\s+/ /go; # Compress multiple spaces
    $txt =~ s/^\s+//o;  # Remove leading space
    $txt =~ s/\s+$//o;  # Remove trailing space

    return $txt;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

COMMIT;

