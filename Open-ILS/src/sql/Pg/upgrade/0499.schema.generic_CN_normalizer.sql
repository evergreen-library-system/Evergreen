BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0499'); -- miker for Steve Callendar

CREATE OR REPLACE FUNCTION asset.label_normalizer_generic(TEXT) RETURNS TEXT AS $func$
    # Created after looking at the Koha C4::ClassSortRoutine::Generic module,
    # thus could probably be considered a derived work, although nothing was
    # directly copied - but to err on the safe side of providing attribution:
    # Copyright (C) 2007 LibLime
    # Copyright (C) 2011 Equinox Software, Inc (Steve Callendar)
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    # Converts the callnumber to uppercase
    # Strips spaces from start and end of the call number
    # Converts anything other than letters, digits, and periods into spaces
    # Collapses multiple spaces into a single underscore
    my $callnum = uc(shift);
    $callnum =~ s/^\s//g;
    $callnum =~ s/\s$//g;
    # NOTE: this previously used underscores, but this caused sorting issues
    # for the "before" half of page 0 on CN browse, sorting CNs containing a
    # decimal before "whole number" CNs
    $callnum =~ s/[^A-Z0-9_.]/ /g;
    $callnum =~ s/ {2,}/ /g;

    return $callnum;
$func$ LANGUAGE PLPERLU;

UPDATE asset.call_number SET id = id;

COMMIT;

