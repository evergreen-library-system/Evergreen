BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;            # Source string
    my $pad = shift;               # string to fill. Typically '0'. This should be a single character.
    my $len = shift;               # length of resultant padded field

    $string =~ s/([0-9]+)/$pad x ($len - length($1)) . $1/eg;

    return $string;
$$ LANGUAGE PLPERLU;


-- Correct any potentially incorrectly padded sortkeys

UPDATE biblio.monograph_part SET label = label;

UPDATE asset.call_number_prefix SET label = label;

-- asset.call_number.label_sortkey doesn't make use of this function

UPDATE asset.call_number_suffix SET label = label;

COMMIT;

