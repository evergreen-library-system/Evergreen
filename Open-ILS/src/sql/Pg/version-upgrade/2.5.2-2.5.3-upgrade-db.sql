--Upgrade Script for 2.5.2 to 2.5.3
\set eg_version '''2.5.3'''

\qecho *** This ALTER TABLE might fail depending on your DB vintage. ***
\qecho *** It should be harmless. ***
ALTER TABLE action.aged_hold_request ADD COLUMN behind_desk BOOLEAN;

BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.5.3', :eg_version);

-- this file is a duplicate of 0851, moved up for better backport clarity

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0862', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.maintain_901 () RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $schema = $_TD->{table_schema};
my $marc = MARC::Record->new_from_xml($_TD->{new}{marc});

my @old901s = $marc->field('901');
$marc->delete_fields(@old901s);

if ($schema eq 'biblio') {
    my $tcn_value = $_TD->{new}{tcn_value};

    # Set TCN value to record ID?
    my $id_as_tcn = spi_exec_query("
        SELECT enabled
        FROM config.global_flag
        WHERE name = 'cat.bib.use_id_for_tcn'
    ");
    if (($id_as_tcn->{processed}) && $id_as_tcn->{rows}[0]->{enabled} eq 't') {
        $tcn_value = $_TD->{new}{id}; 
        $_TD->{new}{tcn_value} = $tcn_value;
    }

    my $new_901 = MARC::Field->new("901", " ", " ",
        "a" => $tcn_value,
        "b" => $_TD->{new}{tcn_source},
        "c" => $_TD->{new}{id},
        "t" => $schema
    );

    if ($_TD->{new}{owner}) {
        $new_901->add_subfields("o" => $_TD->{new}{owner});
    }

    if ($_TD->{new}{share_depth}) {
        $new_901->add_subfields("d" => $_TD->{new}{share_depth});
    }

    $marc->append_fields($new_901);
} elsif ($schema eq 'authority') {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
    );
    $marc->append_fields($new_901);
} elsif ($schema eq 'serial') {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
        "o" => $_TD->{new}{owning_lib},
    );

    if ($_TD->{new}{record}) {
        $new_901->add_subfields("r" => $_TD->{new}{record});
    }

    $marc->append_fields($new_901);
} else {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
    );
    $marc->append_fields($new_901);
}

my $xml = $marc->as_xml_record();
$xml =~ s/\n//sgo;
$xml =~ s/^<\?xml.+\?\s*>//go;
$xml =~ s/>\s+</></go;
$xml =~ s/\p{Cc}//go;

# Embed a version of OpenILS::Application::AppUtils->entityize()
# to avoid having to set PERL5LIB for PostgreSQL as well

$xml = NFC($xml);

# Convert raw ampersands to entities
$xml =~ s/&(?!\S+;)/&amp;/gso;

# Convert Unicode characters to entities
$xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

$xml =~ s/[\x00-\x1f]//go;
$_TD->{new}{marc} = $xml;

return "MODIFY";
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION maintain_control_numbers() RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $record = MARC::Record->new_from_xml($_TD->{new}{marc});
my $schema = $_TD->{table_schema};
my $rec_id = $_TD->{new}{id};

# Short-circuit if maintaining control numbers per MARC21 spec is not enabled
my $enable = spi_exec_query("SELECT enabled FROM config.global_flag WHERE name = 'cat.maintain_control_numbers'");
if (!($enable->{processed}) or $enable->{rows}[0]->{enabled} eq 'f') {
    return;
}

# Get the control number identifier from an OU setting based on $_TD->{new}{owner}
my $ou_cni = 'EVRGRN';

my $owner;
if ($schema eq 'serial') {
    $owner = $_TD->{new}{owning_lib};
} else {
    # are.owner and bre.owner can be null, so fall back to the consortial setting
    $owner = $_TD->{new}{owner} || 1;
}

my $ous_rv = spi_exec_query("SELECT value FROM actor.org_unit_ancestor_setting('cat.marc_control_number_identifier', $owner)");
if ($ous_rv->{processed}) {
    $ou_cni = $ous_rv->{rows}[0]->{value};
    $ou_cni =~ s/"//g; # Stupid VIM syntax highlighting"
} else {
    # Fall back to the shortname of the OU if there was no OU setting
    $ous_rv = spi_exec_query("SELECT shortname FROM actor.org_unit WHERE id = $owner");
    if ($ous_rv->{processed}) {
        $ou_cni = $ous_rv->{rows}[0]->{shortname};
    }
}

my ($create, $munge) = (0, 0);

my @scns = $record->field('035');

foreach my $id_field ('001', '003') {
    my $spec_value;
    my @controls = $record->field($id_field);

    if ($id_field eq '001') {
        $spec_value = $rec_id;
    } else {
        $spec_value = $ou_cni;
    }

    # Create the 001/003 if none exist
    if (scalar(@controls) == 1) {
        # Only one field; check to see if we need to munge it
        unless (grep $_->data() eq $spec_value, @controls) {
            $munge = 1;
        }
    } else {
        # Delete the other fields, as with more than 1 001/003 we do not know which 003/001 to match
        foreach my $control (@controls) {
            $record->delete_field($control);
        }
        $record->insert_fields_ordered(MARC::Field->new($id_field, $spec_value));
        $create = 1;
    }
}

my $cn = $record->field('001')->data();
# Special handling of OCLC numbers, often found in records that lack 003
if ($cn =~ /^o(c[nm]|n)\d/) {
    $cn =~ s/^o(c[nm]|n)0*(\d+)/$2/;
    $record->field('003')->data('OCoLC');
    $create = 0;
}

# Now, if we need to munge the 001, we will first push the existing 001/003
# into the 035; but if the record did not have one (and one only) 001 and 003
# to begin with, skip this process
if ($munge and not $create) {

    my $scn = "(" . $record->field('003')->data() . ")" . $cn;

    # Do not create duplicate 035 fields
    unless (grep $_->subfield('a') eq $scn, @scns) {
        $record->insert_fields_ordered(MARC::Field->new('035', '', '', 'a' => $scn));
    }
}

# Set the 001/003 and update the MARC
if ($create or $munge) {
    $record->field('001')->data($rec_id);
    $record->field('003')->data($ou_cni);

    my $xml = $record->as_xml_record();
    $xml =~ s/\n//sgo;
    $xml =~ s/^<\?xml.+\?\s*>//go;
    $xml =~ s/>\s+</></go;
    $xml =~ s/\p{Cc}//go;

    # Embed a version of OpenILS::Application::AppUtils->entityize()
    # to avoid having to set PERL5LIB for PostgreSQL as well

    $xml = NFC($xml);

    # Convert raw ampersands to entities
    $xml =~ s/&(?!\S+;)/&amp;/gso;

    # Convert Unicode characters to entities
    $xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

    $xml =~ s/[\x00-\x1f]//go;
    $_TD->{new}{marc} = $xml;

    return "MODIFY";
}

return;
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # http://www.loc.gov/catdir/pcc/naco/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

-- Currently, the only difference from naco_normalize is that search_normalize
-- turns apostrophes into spaces, while naco_normalize collapses them.
CREATE OR REPLACE FUNCTION public.search_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # http://www.loc.gov/catdir/pcc/naco/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}][/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

-- add missing behind_desk column


SELECT evergreen.upgrade_deps_block_check('0868', :eg_version);

CREATE OR REPLACE VIEW action.all_hold_request AS
    SELECT DISTINCT
           COALESCE(a.post_code, b.post_code) AS usr_post_code,
           p.home_ou AS usr_home_ou,
           p.profile AS usr_profile,
           EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
           CAST(ahr.requestor <> ahr.usr AS BOOLEAN) AS staff_placed,
           ahr.id,
           ahr.request_time,
           ahr.capture_time,
           ahr.fulfillment_time,
           ahr.checkin_time,
           ahr.return_time,
           ahr.prev_check_time,
           ahr.expire_time,
           ahr.cancel_time,
           ahr.cancel_cause,
           ahr.cancel_note,
           ahr.target,
           ahr.current_copy,
           ahr.fulfillment_staff,
           ahr.fulfillment_lib,
           ahr.request_lib,
           ahr.selection_ou,
           ahr.selection_depth,
           ahr.pickup_lib,
           ahr.hold_type,
           ahr.holdable_formats,
           CASE
           WHEN ahr.phone_notify IS NULL THEN FALSE
           WHEN ahr.phone_notify = '' THEN FALSE
           ELSE TRUE
           END AS phone_notify,
           ahr.email_notify,
           CASE
           WHEN ahr.sms_notify IS NULL THEN FALSE
           WHEN ahr.sms_notify = '' THEN FALSE
           ELSE TRUE
           END AS sms_notify,
           ahr.frozen,
           ahr.thaw_date,
           ahr.shelf_time,
           ahr.cut_in_line,
           ahr.mint_condition,
           ahr.shelf_expire_time,
           ahr.current_shelf_lib,
           ahr.behind_desk
    FROM action.hold_request ahr
         JOIN actor.usr p ON (ahr.usr = p.id)
         LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
         LEFT JOIN actor.usr_address b ON (p.billing_address = b.id)
    UNION ALL
    SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib,
           behind_desk
    FROM action.aged_hold_request;



CREATE OR REPLACE FUNCTION action.age_hold_on_delete () RETURNS TRIGGER AS $$
DECLARE
BEGIN
    -- Archive a copy of the old row to action.aged_hold_request

    INSERT INTO action.aged_hold_request
           (usr_post_code,
            usr_home_ou,
            usr_profile,
            usr_birth_year,
            staff_placed,
            id,
            request_time,
            capture_time,
            fulfillment_time,
            checkin_time,
            return_time,
            prev_check_time,
            expire_time,
            cancel_time,
            cancel_cause,
            cancel_note,
            target,
            current_copy,
            fulfillment_staff,
            fulfillment_lib,
            request_lib,
            selection_ou,
            selection_depth,
            pickup_lib,
            hold_type,
            holdable_formats,
            phone_notify,
            email_notify,
            sms_notify,
            frozen,
            thaw_date,
            shelf_time,
            cut_in_line,
            mint_condition,
            shelf_expire_time,
            current_shelf_lib,
            behind_desk)
      SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib,
           behind_desk
        FROM action.all_hold_request WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';


COMMIT;
