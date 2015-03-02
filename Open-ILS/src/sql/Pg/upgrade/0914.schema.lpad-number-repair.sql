BEGIN;

SELECT evergreen.upgrade_deps_block_check('0914', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;            # Source string
    my $pad = shift;               # string to fill.  Typically '0'. This should be a single character.
    my $len = shift;               # length of resultant padded field
    my $find = $len - 1;

    while ($string =~ /(^|\D)(\d{1,$find})($|\D)/) {
        my $padded = $2;
        $padded = $pad x ($len - length($padded)) . $padded;
        $string = $` . $1 . $padded . $3 . $';
    }

    return $string;
$$ LANGUAGE PLPERLU;

COMMIT;

-- recompute the various normalized label fields that use lpad_number_substrings()
UPDATE biblio.monograph_part SET id = id;
UPDATE asset.call_number_prefix SET id = id;
UPDATE asset.call_number_suffix SET id = id;
