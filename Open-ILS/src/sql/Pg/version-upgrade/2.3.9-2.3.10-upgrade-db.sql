--Upgrade Script for 2.3.9 to 2.3.10
\set eg_version '''2.3.10'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.3.10', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0818', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype ) VALUES (
    'circ.patron_edit.duplicate_patron_check_depth', 'circ',
    oils_i18n_gettext(
        'circ.patron_edit.duplicate_patron_check_depth',
        'Specify search depth for the duplicate patron check in the patron editor',
        'coust',
        'label'),
    oils_i18n_gettext(
        'circ.patron_edit.duplicate_patron_check_depth',
        'When using the patron registration page, the duplicate patron check will use the configured depth to scope the search for duplicate patrons.',
        'coust',
        'description'),
    'integer')
;



-- Evergreen DB patch 0819.schema.acn_dewey_normalizer.sql
--
-- Fixes Dewey call number sorting (per LP# 1150939)
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0819', :eg_version);

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
    my $first_digit_group_idx;
    for (my $i = 0; $i <= $#tokens; $i++) {
        if ($tokens[$i] =~ /^\d+$/) {
            $digit_group_count++;
            if ($digit_group_count == 1) {
                $first_digit_group_idx = $i;
            }
            if (2 == $digit_group_count) {
                $tokens[$i] = sprintf("%-15.15s", $tokens[$i]);
                $tokens[$i] =~ tr/ /0/;
            }
        }
    }
    # Pad the first digit_group if there was only one
    if (1 == $digit_group_count) {
        $tokens[$first_digit_group_idx] .= '_000000000000000'
    }
    my $key = join("_", @tokens);
    $key =~ s/[^\p{IsAlnum}_]//g;

    return $key;

$func$ LANGUAGE PLPERLU;

-- regenerate sort keys for any dewey call numbers
UPDATE asset.call_number SET id = id WHERE label_class = 2;

COMMIT;
