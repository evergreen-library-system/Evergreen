BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0357'); -- dbs

DELETE FROM config.metabib_field_index_norm_map
    WHERE norm IN (
        SELECT id 
            FROM config.index_normalizer
            WHERE func IN ('first_word', 'naco_normalize', 'split_date_range')
    )
    AND field = 18
;

CREATE OR REPLACE FUNCTION public.translate_isbn1013( TEXT ) RETURNS TEXT AS $func$
    use Business::ISBN;
    use strict;
    use warnings;

    # For each ISBN found in a single string containing a set of ISBNs:
    #   * Normalize an incoming ISBN to have the correct checksum and no hyphens
    #   * Convert an incoming ISBN10 or ISBN13 to its counterpart and return

    my $input = shift;
    my $output = '';

    foreach my $word (split(/\s/, $input)) {
        my $isbn = Business::ISBN->new($word);

        # First check the checksum; if it is not valid, fix it and add the original
        # bad-checksum ISBN to the output
        if ($isbn && $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM) {
            $output .= $isbn->isbn() . " ";
            $isbn->fix_checksum();
        }

        # If we now have a valid ISBN, convert it to its counterpart ISBN10/ISBN13
        # and add the normalized original ISBN to the output
        if ($isbn && $isbn->is_valid()) {
            my $isbn_xlated = ($isbn->type eq "ISBN13") ? $isbn->as_isbn10 : $isbn->as_isbn13;
            $output .= $isbn->isbn . " ";

            # If we successfully converted the ISBN to its counterpart, add the
            # converted ISBN to the output as well
            $output .= ($isbn_xlated->isbn . " ") if ($isbn_xlated);
        }
    }
    return $output if $output;

    # If there were no valid ISBNs, just return the raw input
    return $input;
$func$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION public.translate_isbn1013(TEXT) IS $$
/*
 * Copyright (C) 2010 Merrimack Valley Library Consortium
 * Jason Stephenson <jstephenson@mvlc.org>
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 *
 * The translate_isbn1013 function takes an input ISBN and returns the
 * following in a single space-delimited string if the input ISBN is valid:
 *   - The normalized input ISBN (hyphens stripped)
 *   - The normalized input ISBN with a fixed checksum if the checksum was bad
 *   - The ISBN converted to its ISBN10 or ISBN13 counterpart, if possible
 */
$$;

COMMIT;
