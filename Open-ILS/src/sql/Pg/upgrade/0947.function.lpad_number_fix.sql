BEGIN;

SELECT evergreen.upgrade_deps_block_check('0947', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;            # Source string
    my $pad = shift;               # string to fill. Typically '0'. This should be a single character.
    my $len = shift;               # length of resultant padded field

    $string =~ s/([0-9]+)/$pad x ($len - length($1)) . $1/eg;

    return $string;
$$ LANGUAGE PLPERLU;

COMMIT;
