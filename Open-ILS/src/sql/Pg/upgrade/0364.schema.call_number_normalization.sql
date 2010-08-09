BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0364'); -- dbs

CREATE TABLE asset.call_number_class (
    id             bigserial     PRIMARY KEY,
    name           TEXT          NOT NULL,
    normalizer     TEXT          NOT NULL DEFAULT 'asset.normalize_generic'
);

INSERT INTO asset.call_number_class (name, normalizer) VALUES 
    ('Generic', 'asset.label_normalizer_generic'),
    ('Dewey (DDC)', 'asset.label_normalizer_dewey'),
    ('Library of Congress (LC)', 'asset.label_normalizer_lc')
;

ALTER TABLE auditor.asset_call_number_history ADD COLUMN label_class BIGINT;
ALTER TABLE auditor.asset_call_number_history ADD COLUMN label_sortkey TEXT;
ALTER TABLE asset.call_number ADD COLUMN label_class BIGINT DEFAULT 1 NOT NULL REFERENCES asset.call_number_class(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE asset.call_number ADD COLUMN label_sortkey TEXT;
CREATE INDEX asset_call_number_label_sortkey ON asset.call_number(label_sortkey);

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    EXECUTE 'SELECT ' || acnc.normalizer || '(' || 
       quote_literal( NEW.label ) || ')'
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;

    NEW.label_sortkey = sortkey;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.label_normalizer_generic(TEXT) RETURNS TEXT AS $func$
    # Created after looking at the Koha C4::ClassSortRoutine::Generic module,
    # thus could probably be considered a derived work, although nothing was
    # directly copied - but to err on the safe side of providing attribution:
    # Copyright (C) 2007 LibLime
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    # Converts the callnumber to uppercase
    # Strips spaces from start and end of the call number
    # Converts anything other than letters, digits, and periods into underscores
    # Collapses multiple underscores into a single underscore
    my $callnum = uc(shift);
    $callnum =~ s/^\s//g;
    $callnum =~ s/\s$//g;
    $callnum =~ s/[^A-Z0-9_.]/_/g;
    $callnum =~ s/_{2,}/_/g;

    return $callnum;
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION asset.label_normalizer_dewey(TEXT) RETURNS TEXT AS $func$
    # Derived from the Koha C4::ClassSortRoutine::Dewey module
    # Copyright (C) 2007 LibLime
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    my $init = uc(shift);
    $init =~ s/^\s+//;
    $init =~ s/\s+$//;
    $init =~ s!/!!g;
    $init =~ s/^([\p{IsAlpha}]+)/$1 /;
    my @tokens = split /\.|\s+/, $init;
    my $digit_group_count = 0;
    for (my $i = 0; $i <= $#tokens; $i++) {
        if ($tokens[$i] =~ /^\d+$/) {
            $digit_group_count++;
            if (2 == $digit_group_count) {
                $tokens[$i] = sprintf("%-15.15s", $tokens[$i]);
                $tokens[$i] =~ tr/ /0/;
            }
        }
    }
    my $key = join("_", @tokens);
    $key =~ s/[^\p{IsAlnum}_]//g;

    return $key;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION asset.label_normalizer_lc(TEXT) RETURNS TEXT AS $func$
    use strict;
    use warnings;

    # Library::CallNumber::LC is currently hosted at http://code.google.com/p/library-callnumber-lc/
    # The author hopes to upload it to CPAN some day, which would make our lives easier
    use Library::CallNumber::LC;

    my $callnum = Library::CallNumber::LC->new(shift);
    return $callnum->normalize();

$func$ LANGUAGE PLPERLU;

COMMIT;
