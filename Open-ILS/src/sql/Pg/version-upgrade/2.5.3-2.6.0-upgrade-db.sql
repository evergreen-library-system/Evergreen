--Upgrade Script for 2.5.3 to 2.6.0
\set eg_version '''2.6.0'''

\qecho
\qecho **** NOTICE ****
\qecho 'We are disabling all triggers for authority.record_entry outside the '
\qecho 'transaction.  If this upgrade fails, you may want to double-check that '
\qecho 'triggers are reactivated, e.g.:'
\qecho 'ALTER TABLE authority.record_entry ENABLE TRIGGER ALL;'
\qecho
ALTER TABLE authority.record_entry DISABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry DISABLE TRIGGER aaa_auth_ingest_or_delete;
ALTER TABLE authority.record_entry DISABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry DISABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry DISABLE TRIGGER map_thesaurus_to_control_set;

BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.6.0', :eg_version);

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0851', :eg_version);

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

-- Evergreen DB patch XXXX.data.prefer_external_url_OUS.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0853', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'lib.prefer_external_url', 'lib',
  'Use external "library information URL" in copy table, if available',
  'If set to true, the library name in the copy details section will link to the URL associated with the "Library information URL" library setting rather than the library information page generated by Evergreen.',
  'bool', null
);


SELECT evergreen.upgrade_deps_block_check('0854', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    553,
    'UPDATE_ORG_UNIT_SETTING.circ.min_item_price',
    oils_i18n_gettext(
        553,
        'UPDATE_ORG_UNIT_SETTING.circ.min_item_price',
        'ppl',
        'description'
    )
), (
	554,
    'UPDATE_ORG_UNIT_SETTING.circ.max_item_price',
    oils_i18n_gettext(
        554,
        'UPDATE_ORG_UNIT_SETTING.circ.max_item_price',
        'ppl',
        'description'
    )
);

INSERT into config.org_unit_setting_type
    ( name, grp, label, description, datatype, fm_class )
VALUES (
    'circ.min_item_price',
	'finance',
    oils_i18n_gettext(
        'circ.min_item_price',
        'Minimum Item Price',
        'coust', 'label'),
    oils_i18n_gettext(
        'circ.min_item_price',
        'When charging for lost items, charge this amount as a minimum.',
        'coust', 'description'),
    'currency',
    NULL
), (
    'circ.max_item_price',
    'finance',
    oils_i18n_gettext(
        'circ.max_item_price',
        'Maximum Item Price',
        'coust', 'label'),
    oils_i18n_gettext(
        'circ.max_item_price',
        'When charging for lost items, limit the charge to this as a maximum.',
        'coust', 'description'),
    'currency',
    NULL
);

-- Compiled list of all changed functions and views where we went from:
--   array_accum() to array_agg()
--   array_to_string(array_agg()) to string_agg()


SELECT evergreen.upgrade_deps_block_check('0855', :eg_version);

-- from 000.functions.general.sql


-- from 002.functions.config.sql

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(string_agg(output,' '),$4,'','g') FROM oils_xpath_table('id', 'marc', $1, $3, 'id='||$2)x(id INT, output TEXT);
$$ LANGUAGE SQL;


-- from 011.schema.authority.sql

CREATE OR REPLACE FUNCTION authority.axis_authority_tags(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(field) FROM authority.browse_axis_authority_field_map WHERE axis = $1;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.axis_authority_tags_refs(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
       SELECT  unnest(ARRAY_CAT(
                 ARRAY[a.field],
                 (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.field)
             )) y
       FROM  authority.browse_axis_authority_field_map a
       WHERE axis = $1) x
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(authority_field) FROM authority.control_set_bib_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags_refs(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.authority_field],
                    (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.authority_field)
                )) y
      FROM  authority.control_set_bib_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(id) FROM authority.control_set_authority_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags_refs(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.id],
                    (SELECT ARRAY_AGG(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.id)
                )) y
      FROM  authority.control_set_authority_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;


-- from 012.schema.vandelay.sql

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT, attr_defs TEXT[]) RETURNS hstore AS $_$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE name IN (SELECT * FROM UNNEST(attr_defs)) ORDER BY format LOOP

        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  STRING_AGG(x.value, COALESCE(attr_def.joiner,' ')) INTO attr_value
              FROM  vandelay.flatten_marc(xml) AS x
              WHERE x.tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL
                            THEN POSITION(x.subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                        END
              GROUP BY x.tag
              ORDER BY x.tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field(xml, attr_def.fixed_field);

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(xml,xfrm.xslt);
                ELSE
                    transformed_xml := xml;
                END IF;

                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  m.value::TEXT INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(xml) v
                    JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf
              LIMIT 1; -- Just in case ...

        END IF;

        -- apply index normalizers to attr_value
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
              WHERE attr = attr_def.name
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_nullable( attr_value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO attr_value;

        END LOOP;

        -- Add the new value to the hstore
        new_attrs := new_attrs || hstore( attr_def.name, attr_value );

    END LOOP;

    RETURN new_attrs;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT ) RETURNS hstore AS $_$
    SELECT vandelay.extract_rec_attrs( $1, (SELECT ARRAY_AGG(name) FROM config.record_attr_definition));
$_$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT, bucket_id INTEGER 
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    svf_rstore  HSTORE;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);
    svf_rstore := vandelay.extract_rec_attrs(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(match_set_id, tags_rstore);

    query_ := 'SELECT DISTINCT(record), ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT STRING_AGG(
        'COALESCE(n' || q::TEXT || '.quality, 0)', ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT STRING_AGG(j, E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n';

    -- join the record bucket
    IF bucket_id IS NOT NULL THEN
        query_ := query_ || 'JOIN container.biblio_record_entry_bucket_item ' ||
            'brebi ON (brebi.target_biblio_record_entry = record ' ||
            'AND brebi.bucket = ' || bucket_id || E')\n';
    END IF;

    query_ := query_ || 'JOIN biblio.record_entry bre ON (bre.id = record) ' || 'WHERE ' || wq || ' AND not bre.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore, svf_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $func$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_AGG(tag || (COALESCE(subfield, ''))),
            ARRAY_AGG(value)
        )
        FROM (
            SELECT  tag, subfield, ARRAY_AGG(value)::TEXT AS value
              FROM  (SELECT tag,
                            subfield,
                            CASE WHEN tag = '020' THEN -- caseless -- isbn
                                LOWER((REGEXP_MATCHES(value,$$^(\S{10,17})$$))[1] || '%')
                            WHEN tag = '022' THEN -- caseless -- issn
                                LOWER((REGEXP_MATCHES(value,$$^(\S{4}[- ]?\S{4})$$))[1] || '%')
                            WHEN tag = '024' THEN -- caseless -- upc (other)
                                LOWER(value || '%')
                            ELSE
                                value
                            END AS value
                      FROM  vandelay.flatten_marc(record_xml)) x
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point,
    tags_rstore HSTORE
) RETURNS TEXT AS $$
DECLARE
    q           TEXT;
    i           INTEGER;
    this_op     TEXT;
    children    INTEGER[];
    child       vandelay.match_set_point;
BEGIN
    SELECT ARRAY_AGG(id) INTO children FROM vandelay.match_set_point
        WHERE parent = node.id;

    IF ARRAY_LENGTH(children, 1) > 0 THEN
        this_op := vandelay._get_expr_render_one(node);
        q := '(';
        i := 1;
        WHILE children[i] IS NOT NULL LOOP
            SELECT * INTO child FROM vandelay.match_set_point
                WHERE id = children[i];
            IF i > 1 THEN
                q := q || ' ' || this_op || ' ';
            END IF;
            i := i + 1;
            q := q || vandelay.get_expr_from_match_set_point(child, tags_rstore);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node, tags_rstore);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;


-- from 030.schema.metabib.sql

CREATE OR REPLACE FUNCTION biblio.extract_located_uris( bib_id BIGINT, marcxml TEXT, editor_id INT ) RETURNS VOID AS $func$
DECLARE
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner_list  TEXT[];
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;
BEGIN

    -- Clear any URI mappings and call numbers for this bib.
    -- This leads to acn / auricnm inflation, but also enables
    -- old acn/auricnm's to go away and for bibs to be deleted.
    FOR uri_cn_id IN SELECT id FROM asset.call_number WHERE record = bib_id AND label = '##URI##' AND NOT deleted LOOP
        DELETE FROM asset.uri_call_number_map WHERE call_number = uri_cn_id;
        DELETE FROM asset.call_number WHERE id = uri_cn_id;
    END LOOP;

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()',uri_xml))[1];
            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];

            IF uri_label IS NULL THEN
                uri_label := uri_href;
            END IF;
            CONTINUE WHEN uri_href IS NULL;

            -- Get the distinct list of libraries wanting to use 
            SELECT  ARRAY_AGG(
                        DISTINCT REGEXP_REPLACE(
                            x,
                            $re$^.*?\((\w+)\).*$$re$,
                            E'\\1'
                        )
                    ) INTO uri_owner_list
              FROM  UNNEST(
                        oils_xpath(
                            '//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',
                            uri_xml
                        )
                    )x;

            IF ARRAY_UPPER(uri_owner_list,1) > 0 THEN

                -- look for a matching uri
                IF uri_use IS NULL THEN
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active;
                    END IF;
                ELSE
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                    END IF;
                END IF;

                FOR j IN 1 .. ARRAY_UPPER(uri_owner_list, 1) LOOP
                    uri_owner := uri_owner_list[j];

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
                    CONTINUE WHEN NOT FOUND;

                    -- we need a call number to link through
                    SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    IF NOT FOUND THEN
                        INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                            VALUES (uri_owner_id, bib_id, 'now', 'now', editor_id, editor_id, '##URI##');
                        SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    END IF;

                    -- now, link them if they're not already
                    SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    IF NOT FOUND THEN
                        INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
                    END IF;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- from 100.circ_matrix.sql

CREATE OR REPLACE FUNCTION actor.calculate_system_penalties( match_user INT, context_org INT ) RETURNS SETOF actor.usr_standing_penalty AS $func$
DECLARE
    user_object         actor.usr%ROWTYPE;
    new_sp_row          actor.usr_standing_penalty%ROWTYPE;
    existing_sp_row     actor.usr_standing_penalty%ROWTYPE;
    collections_fines   permission.grp_penalty_threshold%ROWTYPE;
    max_fines           permission.grp_penalty_threshold%ROWTYPE;
    max_overdue         permission.grp_penalty_threshold%ROWTYPE;
    max_items_out       permission.grp_penalty_threshold%ROWTYPE;
    max_lost            permission.grp_penalty_threshold%ROWTYPE;
    max_longoverdue     permission.grp_penalty_threshold%ROWTYPE;
    tmp_grp             INT;
    items_overdue       INT;
    items_out           INT;
    items_lost          INT;
    items_longoverdue   INT;
    context_org_list    INT[];
    current_fines        NUMERIC(8,2) := 0.0;
    tmp_fines            NUMERIC(8,2);
    tmp_groc            RECORD;
    tmp_circ            RECORD;
    tmp_org             actor.org_unit%ROWTYPE;
    tmp_penalty         config.standing_penalty%ROWTYPE;
    tmp_depth           INTEGER;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Max fines
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a high fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 1 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 1;

        SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 1;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max overdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many overdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_overdue FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 2 AND org_unit = tmp_org.id;

            IF max_overdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_overdue.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_overdue.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_overdue.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 2;

        SELECT  INTO items_overdue COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_overdue.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND circ.due_date < NOW()
            AND (circ.stop_fines = 'MAXFINES' OR circ.stop_fines IS NULL);

        IF items_overdue >= max_overdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_overdue.org_unit;
            new_sp_row.standing_penalty := 2;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max out
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many checked out items
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_items_out FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 3 AND org_unit = tmp_org.id;

            IF max_items_out.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_items_out.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;


    -- Fail if the user has too many items checked out
    IF max_items_out.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_items_out.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 3;

        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_items_out.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
                AND circ.checkin_time IS NULL
                AND (circ.stop_fines IN (
                    SELECT 'MAXFINES'::TEXT
                    UNION ALL
                    SELECT 'LONGOVERDUE'::TEXT
                    UNION ALL
                    SELECT 'LOST'::TEXT
                    WHERE 'true' ILIKE
                    (
                        SELECT CASE
                            WHEN (SELECT value FROM actor.org_unit_ancestor_setting('circ.tally_lost', circ.circ_lib)) ILIKE 'true' THEN 'true'
                            ELSE 'false'
                        END
                    )
                    UNION ALL
                    SELECT 'CLAIMSRETURNED'::TEXT
                    WHERE 'false' ILIKE
                    (
                        SELECT CASE
                            WHEN (SELECT value FROM actor.org_unit_ancestor_setting('circ.do_not_tally_claims_returned', circ.circ_lib)) ILIKE 'true' THEN 'true'
                            ELSE 'false'
                        END
                    )
                    ) OR circ.stop_fines IS NULL)
                AND xact_finish IS NULL;

           IF items_out >= max_items_out.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_items_out.org_unit;
            new_sp_row.standing_penalty := 3;
            RETURN NEXT new_sp_row;
           END IF;
    END IF;

    -- Start over for max lost
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many lost items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_lost FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 5 AND org_unit = tmp_org.id;

            IF max_lost.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_lost.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_lost.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
            FROM  actor.usr_standing_penalty
            WHERE usr = match_user
                AND org_unit = max_lost.org_unit
                AND (stop_date IS NULL or stop_date > NOW())
                AND standing_penalty = 5;

        SELECT  INTO items_lost COUNT(*)
        FROM  action.circulation circ
            JOIN  actor.org_unit_full_path( max_lost.org_unit ) fp ON (circ.circ_lib = fp.id)
        WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines = 'LOST')
            AND xact_finish IS NULL;

        IF items_lost >= max_lost.threshold::INT AND 0 < max_lost.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_lost.org_unit;
            new_sp_row.standing_penalty := 5;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max longoverdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many longoverdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_longoverdue 
                FROM permission.grp_penalty_threshold 
                WHERE grp = tmp_grp AND 
                    penalty = 35 AND 
                    org_unit = tmp_org.id;

            IF max_longoverdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp 
                    FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_longoverdue.threshold IS NOT NULL 
                OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_longoverdue.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
            FROM  actor.usr_standing_penalty
            WHERE usr = match_user
                AND org_unit = max_longoverdue.org_unit
                AND (stop_date IS NULL or stop_date > NOW())
                AND standing_penalty = 35;

        SELECT INTO items_longoverdue COUNT(*)
        FROM action.circulation circ
            JOIN actor.org_unit_full_path( max_longoverdue.org_unit ) fp 
                ON (circ.circ_lib = fp.id)
        WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines = 'LONGOVERDUE')
            AND xact_finish IS NULL;

        IF items_longoverdue >= max_longoverdue.threshold::INT 
                AND 0 < max_longoverdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_longoverdue.org_unit;
            new_sp_row.standing_penalty := 35;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;


    -- Start over for collections warning
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a collections-level fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 4 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 4;

        SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 4;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for in collections
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Remove the in-collections penalty if the user has paid down enough
    -- This penalty is different, because this code is not responsible for creating 
    -- new in-collections penalties, only for removing them
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 30 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        -- first, see if the user had paid down to the threshold
        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines IS NULL OR current_fines <= max_fines.threshold THEN
            -- patron has paid down enough

            SELECT INTO tmp_penalty * FROM config.standing_penalty WHERE id = 30;

            IF tmp_penalty.org_depth IS NOT NULL THEN

                -- since this code is not responsible for applying the penalty, it can't 
                -- guarantee the current context org will match the org at which the penalty 
                --- was applied.  search up the org tree until we hit the configured penalty depth
                SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;
                SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;

                WHILE tmp_depth >= tmp_penalty.org_depth LOOP

                    RETURN QUERY
                        SELECT  *
                          FROM  actor.usr_standing_penalty
                          WHERE usr = match_user
                                AND org_unit = tmp_org.id
                                AND (stop_date IS NULL or stop_date > NOW())
                                AND standing_penalty = 30;

                    IF tmp_org.parent_ou IS NULL THEN
                        EXIT;
                    END IF;

                    SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;
                    SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;
                END LOOP;

            ELSE

                -- no penalty depth is defined, look for exact matches

                RETURN QUERY
                    SELECT  *
                      FROM  actor.usr_standing_penalty
                      WHERE usr = match_user
                            AND org_unit = max_fines.org_unit
                            AND (stop_date IS NULL or stop_date > NOW())
                            AND standing_penalty = 30;
            END IF;
    
        END IF;

    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


-- from 110.hold_matrix.sql

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object     asset.call_number%ROWTYPE;
    item_status_object  config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
    hold_penalty TEXT;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( pickup_ou );

    result.success := TRUE;

    -- The HOLD penalty block only applies to new holds.
    -- The CAPTURE penalty block applies to existing holds.
    hold_penalty := 'HOLD';
    IF retargetting THEN
        hold_penalty := 'CAPTURE';
    END IF;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO item_status_object * FROM config.copy_status WHERE id = item_object.status;
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_object.holdable IS FALSE THEN
        result.fail_part := 'item.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_status_object.holdable IS FALSE THEN
        result.fail_part := 'status.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_location_object.holdable IS FALSE THEN
        result.fail_part := 'location.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;
 
    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE '%' || hold_penalty || '%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP
    
            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_cn_object.owning_lib);
        ELSE
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_object.circ_lib);
        END IF;
        IF use_active_date = 'true' THEN
            age_protect_date := COALESCE(item_object.active_date, NOW());
        ELSE
            age_protect_date := item_object.create_date;
        END IF;
        IF age_protect_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


-- from 300.schema.staged_search.sql


-- from 990.schema.unapi.sql

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT)
RETURNS anyarray AS $$
    SELECT ARRAY_AGG(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2;
$$ LANGUAGE SQL STABLE;


-- from 999.functions.global.sql

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
			' tag="856"' ||
			' ind1="' || FIRST(ind1) || '"'  ||
			' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

	-- Find and move metarecords to the target record
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
			AND owning_lib = source_cn.owning_lib
			AND record = target_record
			AND NOT deleted;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial subscriptions targeting the source record ...
	FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.subscription
		  SET	record_entry = target_record
		  WHERE	id = ser_sub.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find booking resource types targeting the source record ...
	FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	booking.resource_type
		  SET	record = target_record
		  WHERE	id = booking.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq lineitems targeting the source record ...
	FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.lineitem
		  SET	eg_bib_id = target_record
		  WHERE	id = acq_lineitem.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq user purchase requests targeting the source record ...
	FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.user_request
		  SET	eg_bib = target_record
		  WHERE	id = acq_request.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find parts attached to the source ...
	FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

		SELECT	INTO target_part *
		  FROM	biblio.monograph_part
		  WHERE	label = source_part.label
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copy-part maps to that, and ...
			UPDATE	asset.copy_part_map
			  SET	part = target_part.id
			  WHERE	part = source_part.id;

			-- ... move P holds to the move-target part
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_part.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the part to the target record
			UPDATE	biblio.monograph_part
			  SET	record = target_record
			  WHERE	id = source_part.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find multi_home items attached to the source ...
	FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	biblio.peer_bib_copy_map
		  SET	peer_record = target_record
		  WHERE	id = multi_home.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- And delete mappings where the item's home bib was merged with the peer bib
	DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
		SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
		FROM asset.copy WHERE id = target_copy
	);

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

-- from reporter-schema.sql

CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT	r.id,
	s.metarecord,
	r.fingerprint,
	r.quality,
	r.tcn_source,
	r.tcn_value,
	title.value AS title,
	uniform_title.value AS uniform_title,
	author.value AS author,
	publisher.value AS publisher,
	SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
	series_title.value AS series_title,
	series_statement.value AS series_statement,
	summary.value AS summary,
	ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
	ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
	ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM	biblio.record_entry r
	JOIN metabib.metarecord_source_map s ON (s.source = r.id)
	LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
	LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
	LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
	LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    STRING_AGG(DISTINCT publisher.value, ', ') AS publisher,
    STRING_AGG(DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$), ', ') AS pubdate,
    CASE WHEN ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') )
    END AS isbn,
    CASE WHEN ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') )
    END AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;



SELECT evergreen.upgrade_deps_block_check('0856', :eg_version);

CREATE OR REPLACE FUNCTION metabib.staged_browse(
    query                   TEXT,
    fields                  INT[],
    context_org             INT,
    context_locations       INT[],
    staff                   BOOL,
    browse_superpage_size   INT,
    count_up_from_zero      BOOL,   -- if false, count down from -1
    result_limit            INT,
    next_pivot_pos          INT
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    OPEN curs FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;


        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        SELECT INTO all_arecords, result_row.sees, afields
                ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

          FROM  metabib.browse_entry_simple_heading_map mbeshm
                JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    ash.atag = map.authority_field
                    AND map.metabib_field = ANY(fields)
                )
          WHERE mbeshm.entry = rec.id;


        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_brecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.sources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_brecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    '1::INT AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, until we've
                -- either exhausted that set of records or found at least 1
                -- visible record.

                SELECT INTO result_row.sources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;

            -- Accurate?  Well, probably.
            result_row.accurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_arecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.asources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_arecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    '1::INT AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, via
                -- authority until we've either exhausted that set of records
                -- or found at least 1 visible record.

                SELECT INTO result_row.asources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;


            -- Accurate?  Well, probably.
            result_row.aaccurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$p$ LANGUAGE PLPGSQL;


/*
 * Copyright (C) 2014  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */



SELECT evergreen.upgrade_deps_block_check('0857', :eg_version);

INSERT INTO config.global_flag (name, enabled, label)
VALUES (
    'opac.located_uri.act_as_copy',
    FALSE,
    oils_i18n_gettext(
        'opac.located_uri.act_as_copy',
        'When enabled, Located URIs will provide visiblity behavior identical to copies.',
        'cgf',
        'label'
    )
);

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL,
    deleted_search  BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

    luri_as_copy        BOOL;
BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    SELECT COALESCE( enabled, FALSE ) INTO luri_as_copy FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy';

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        IF luri_as_copy THEN
            SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_full_path( param_search_ou );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );
        END IF;

    ELSIF param_search_ou < 0 THEN
        SELECT ARRAY_AGG(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP

            IF luri_as_copy THEN
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_full_path( tmp_int );
            ELSE
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            END IF;

            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT ARRAY_AGG(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
            IF luri_as_copy THEN
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_full_path( param_pref_ou );
            ELSE
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( param_pref_ou );
            END IF;

        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        IF NOT deleted_search THEN

            PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
                deleted_count := deleted_count + 1;
                CONTINUE;
            END IF;

            PERFORM 1
              FROM  biblio.record_entry b
                    JOIN config.bib_source s ON (b.source = s.id)
              WHERE s.transcendant
                    AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

            IF FOUND THEN
                -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;

                tmp_int := 1;
                IF metarecord THEN
                    SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
                END IF;

                IF tmp_int = 1 THEN
                    current_res.record = core_result.records[1];
                ELSE
                    current_res.record = NULL;
                END IF;

                RETURN NEXT current_res;

                CONTINUE;
            END IF;

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                    JOIN asset.uri uri ON (map.uri = uri.id)
              WHERE NOT cn.deleted
                    AND cn.label = '##URI##'
                    AND uri.active
                    AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
              LIMIT 1;

            IF FOUND THEN
                -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;

                tmp_int := 1;
                IF metarecord THEN
                    SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
                END IF;

                IF tmp_int = 1 THEN
                    current_res.record = core_result.records[1];
                ELSE
                    current_res.record = NULL;
                END IF;

                RETURN NEXT current_res;

                CONTINUE;
            END IF;

            IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF staff IS NULL OR NOT staff THEN

                PERFORM 1
                  FROM  asset.opac_visible_copies
                  WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                      WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            ELSE

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        PERFORM 1
                          FROM  asset.call_number cn
                                JOIN asset.copy cp ON (cp.call_number = cn.id)
                          WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                AND NOT cp.deleted
                          LIMIT 1;

                        IF FOUND THEN
                            -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                            excluded_count := excluded_count + 1;
                            CONTINUE;
                        END IF;
                    END IF;

                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ($5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT record_has_holdable_copy FROM asset.record_has_holdable_copy($1)) AS has_holdable
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_record_copy_count($2, $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($9,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT(
                            name monograph_parts,
                            (SELECT XMLAGG(bmp) FROM (
                                SELECT  unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE)
                                  FROM  biblio.monograph_part
                                  WHERE record = $1
                            )x)
                        )
                     ELSE NULL
                 END,
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes($1, $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), uris.rank, name, label_sortkey
                        FROM evergreen.located_uris($1, $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('acp' = ANY ($5)) THEN
                     XMLELEMENT(
                         name foreign_copies,
                         (SELECT XMLAGG(acp) FROM (
                            SELECT  unapi.acp(p.target_copy,'xml','copy',evergreen.array_remove_item_by_value($5,'acp'), $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND p.peer_record = $1
                            LIMIT ($6 -> 'acp')::INT
                            OFFSET ($7 -> 'acp')::INT
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('0858', :eg_version);

-- Fix faulty seed data. Otherwise for ptype 'f' we have subfield 'e'
-- overlapping subfield 'd'
UPDATE config.marc21_physical_characteristic_subfield_map
    SET start_pos = 5
    WHERE ptype_key = 'f' AND subfield = 'e';

-- Evergreen DB patch 0859.data.staff-initials-settings.sql
--
-- More granular configuration settings for requiring use of staff initials
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0859', :eg_version);

-- add new granular settings for requiring use of staff initials
INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.staff.require_initials.patron_standing_penalty',
        'gui',
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_standing_penalty',
            'Require staff initials for entry/edit of patron standing penalties and messages.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_standing_penalty',
            'Appends staff initials and edit date into patron standing penalties and messages.',
            'coust',
            'description'
        ),
        'bool'
    ), (
        'ui.staff.require_initials.patron_info_notes',
        'gui',
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_info_notes',
            'Require staff initials for entry/edit of patron notes.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_info_notes',
            'Appends staff initials and edit date into patron note content.',
            'coust',
            'description'
        ),
        'bool'
    ), (
        'ui.staff.require_initials.copy_notes',
        'gui',
        oils_i18n_gettext(
            'ui.staff.require_initials.copy_notes',
            'Require staff initials for entry/edit of copy notes.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.staff.require_initials.copy_notes',
            'Appends staff initials and edit date into copy note content..',
            'coust',
            'description'
        ),
        'bool'
    );

-- Update any existing setting so that the original set value is now passed to
-- one of the newer settings.

UPDATE actor.org_unit_setting
SET name = 'ui.staff.require_initials.patron_standing_penalty'
WHERE name = 'ui.staff.require_initials';

-- Add similar values for new settings as old ones to preserve existing configured
-- functionality.

INSERT INTO actor.org_unit_setting (org_unit, name, value)
SELECT org_unit, 'ui.staff.require_initials.patron_info_notes', value
FROM actor.org_unit_setting
WHERE name = 'ui.staff.require_initials.patron_standing_penalty';

INSERT INTO actor.org_unit_setting (org_unit, name, value)
SELECT org_unit, 'ui.staff.require_initials.copy_notes', value
FROM actor.org_unit_setting
WHERE name = 'ui.staff.require_initials.patron_standing_penalty';

-- Update setting logs so that the original setting name's history is now transferred
-- over to one of the newer settings.

UPDATE config.org_unit_setting_type_log
SET field_name = 'ui.staff.require_initials.patron_standing_penalty'
WHERE field_name = 'ui.staff.require_initials';

-- Remove the old setting entirely

DELETE FROM config.org_unit_setting_type WHERE name = 'ui.staff.require_initials';


-- oh, the irony
SELECT evergreen.upgrade_deps_block_check('0860', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.array_overlap_check (/* field */) RETURNS TRIGGER AS $$
DECLARE
    fld     TEXT;
    cnt     INT;
BEGIN
    fld := TG_ARGV[0];
    EXECUTE 'SELECT COUNT(*) FROM '|| TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME ||' WHERE '|| fld ||' && ($1).'|| fld INTO cnt USING NEW;
    IF cnt > 0 THEN
        RAISE EXCEPTION 'Cannot insert duplicate array into field % of table %', fld, TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_deprecates ( my_db_patch TEXT ) RETURNS SETOF evergreen.patch AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version = ANY(d.deprecates))
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that are superseded by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_supersedes ( my_db_patch TEXT ) RETURNS SETOF evergreen.patch AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version = ANY(d.supersedes))
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION evergreen.upgrade_deps_block_check ( my_db_patch TEXT, my_applied_to TEXT ) RETURNS BOOL AS $$
DECLARE 
    deprecates TEXT;
    supersedes TEXT;
BEGIN
    IF NOT evergreen.upgrade_verify_no_dep_conflicts( my_db_patch ) THEN
        SELECT  STRING_AGG(patch, ', ') INTO deprecates FROM evergreen.upgrade_list_applied_deprecates(my_db_patch);
        SELECT  STRING_AGG(patch, ', ') INTO supersedes FROM evergreen.upgrade_list_applied_supersedes(my_db_patch);
        RAISE EXCEPTION '
Upgrade script % can not be applied:
  applied deprecated scripts %
  applied superseded scripts %
  deprecated by %
  superseded by %',
            my_db_patch,
            (SELECT ARRAY_AGG(patch) FROM evergreen.upgrade_list_applied_deprecates(my_db_patch)),
            (SELECT ARRAY_AGG(patch) FROM evergreen.upgrade_list_applied_supersedes(my_db_patch)),
            evergreen.upgrade_list_applied_deprecated(my_db_patch),
            evergreen.upgrade_list_applied_superseded(my_db_patch);
    END IF;

    INSERT INTO config.upgrade_log (version, applied_to) VALUES (my_db_patch, my_applied_to);
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('0861', :eg_version);

CREATE INDEX authority_record_entry_create_date_idx ON authority.record_entry ( create_date );
CREATE INDEX authority_record_entry_edit_date_idx ON authority.record_entry ( edit_date );



SELECT evergreen.upgrade_deps_block_check('0863', :eg_version);


-- cheat sheet for enabling Stripe payments:
--  'credit.payments.allow' must be true, and among other things it drives the
--      opac to render a payment form at all
--  NEW 'credit.processor.stripe.enabled' must be true  (kind of redundant but
--      my fault for setting the precedent with c.p.{authorizenet|paypal|payflowpro}.enabled)
--  'credit.default.processor' must be 'Stripe'
--  NEW 'credit.processor.stripe.pubkey' must be set
--  NEW 'credit.processor.stripe.secretkey' must be set

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

    ( 'credit.processor.stripe.enabled', 'credit',
    oils_i18n_gettext('credit.processor.stripe.enabled',
        'Enable Stripe payments',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.stripe.enabled',
        'Enable Stripe payments',
        'coust', 'description'),
    'bool', null)

,( 'credit.processor.stripe.pubkey', 'credit',
    oils_i18n_gettext('credit.processor.stripe.pubkey',
        'Stripe publishable key',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.stripe.pubkey',
        'Stripe publishable key',
        'coust', 'description'),
    'string', null)

,( 'credit.processor.stripe.secretkey', 'credit',
    oils_i18n_gettext('credit.processor.stripe.secretkey',
        'Stripe secret key',
        'coust', 'label'),
    oils_i18n_gettext('credit.processor.stripe.secretkey',
        'Stripe secret key',
        'coust', 'description'),
    'string', null)
;

UPDATE config.org_unit_setting_type
SET description = 'This might be "AuthorizeNet", "PayPal", "PayflowPro", or "Stripe".'
WHERE name = 'credit.processor.default' AND description = 'This might be "AuthorizeNet", "PayPal", etc.'; -- don't clobber local edits or i18n


SELECT evergreen.upgrade_deps_block_check('0864', :eg_version);

CREATE EXTENSION IF NOT EXISTS intarray WITH SCHEMA public;

-- while we have this opportunity, and before we start collecting 
-- CCVM IDs (below) carve out a nice space for stock ccvm values
UPDATE config.coded_value_map SET id = id + 10000 WHERE id > 556;
SELECT SETVAL('config.coded_value_map_id_seq'::TEXT, 
    (SELECT GREATEST(max(id), 10000) FROM config.coded_value_map));

ALTER TABLE config.record_attr_definition ADD COLUMN multi BOOL NOT NULL DEFAULT TRUE, ADD COLUMN composite BOOL NOT NULL DEFAULT FALSE;

UPDATE  config.record_attr_definition
  SET   multi = FALSE
  WHERE name IN ('bib_level','control_type','pubdate','cat_form','enc_level','item_type','titlesort','authorsort');

CREATE OR REPLACE FUNCTION vandelay.marc21_physical_characteristics( marc TEXT) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
DECLARE
    rowid   INT := 0;
    _007    TEXT;
    ptype   config.marc21_physical_characteristic_type_map%ROWTYPE;
    psf     config.marc21_physical_characteristic_subfield_map%ROWTYPE;
    pval    config.marc21_physical_characteristic_value_map%ROWTYPE;
    retval  biblio.marc21_physical_characteristics%ROWTYPE;
BEGIN

    FOR _007 IN SELECT oils_xpath_string('//*', value) FROM UNNEST(oils_xpath('//*[@tag="007"]', marc)) x(value) LOOP
        IF _007 IS NOT NULL AND _007 <> '' THEN
            SELECT * INTO ptype FROM config.marc21_physical_characteristic_type_map WHERE ptype_key = SUBSTRING( _007, 1, 1 );

            IF ptype.ptype_key IS NOT NULL THEN
                FOR psf IN SELECT * FROM config.marc21_physical_characteristic_subfield_map WHERE ptype_key = ptype.ptype_key LOOP
                    SELECT * INTO pval FROM config.marc21_physical_characteristic_value_map WHERE ptype_subfield = psf.id AND value = SUBSTRING( _007, psf.start_pos + 1, psf.length );

                    IF pval.id IS NOT NULL THEN
                        rowid := rowid + 1;
                        retval.id := rowid;
                        retval.ptype := ptype.ptype_key;
                        retval.subfield := psf.id;
                        retval.value := pval.id;
                        RETURN NEXT retval;
                    END IF;

                END LOOP;
            END IF;
        END IF;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field_list( marc TEXT, ff TEXT ) RETURNS TEXT[] AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
    collection  TEXT[] := '{}'::TEXT[];
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        IF ff_pos.tag = 'ldr' THEN
            val := oils_xpath_string('//*[local-name()="leader"]', marc);
            IF val IS NOT NULL THEN
                val := SUBSTRING( val, ff_pos.start_pos + 1, ff_pos.length );
                collection := collection || val;
            END IF;
        ELSE
            FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
                val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
                collection := collection || val;
            END LOOP;
        END IF;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        collection := collection || val;
    END LOOP;

    RETURN collection;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field_list( rid BIGINT, ff TEXT ) RETURNS TEXT[] AS $func$
    SELECT * FROM vandelay.marc21_extract_fixed_field_list( (SELECT marc FROM biblio.record_entry WHERE id = $1), $2 );
$func$ LANGUAGE SQL;

-- DECREMENTING serial starts at -1
CREATE SEQUENCE metabib.uncontrolled_record_attr_value_id_seq INCREMENT BY -1;

CREATE TABLE metabib.uncontrolled_record_attr_value (
    id      BIGINT  PRIMARY KEY DEFAULT nextval('metabib.uncontrolled_record_attr_value_id_seq'),
    attr    TEXT    NOT NULL REFERENCES config.record_attr_definition (name),
    value   TEXT    NOT NULL
);
CREATE UNIQUE INDEX muv_once_idx ON metabib.uncontrolled_record_attr_value (attr,value);

CREATE TABLE metabib.record_attr_vector_list (
    source  BIGINT  PRIMARY KEY REFERENCES  biblio.record_entry (id),
    vlist   INT[]   NOT NULL -- stores id from ccvm AND murav
);
CREATE INDEX mrca_vlist_idx ON metabib.record_attr_vector_list USING gin ( vlist gin__int_ops );

CREATE TABLE metabib.record_sorter (
    id      BIGSERIAL   PRIMARY KEY,
    source  BIGINT      NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
    attr    TEXT        NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE,
    value   TEXT        NOT NULL
);
CREATE INDEX metabib_sorter_source_idx ON metabib.record_sorter (source); -- we may not need one of this or the next ... stats will tell
CREATE INDEX metabib_sorter_s_a_idx ON metabib.record_sorter (source, attr);
CREATE INDEX metabib_sorter_a_v_idx ON metabib.record_sorter (attr, value);

CREATE TEMP TABLE attr_set ON COMMIT DROP AS SELECT  DISTINCT id AS source, (each(attrs)).key,(each(attrs)).value FROM metabib.record_attr;
DELETE FROM attr_set WHERE BTRIM(value) = '';

-- Grab sort values for the new sorting mechanism
INSERT INTO metabib.record_sorter (source,attr,value)
    SELECT  a.source, a.key, a.value
      FROM  attr_set a
            JOIN config.record_attr_definition d ON (d.name = a.key AND d.sorter AND a.value IS NOT NULL);

-- Rewrite uncontrolled SVF record attrs as the seeds of an intarray vector
INSERT INTO metabib.uncontrolled_record_attr_value (attr,value)
    SELECT  DISTINCT a.key, a.value
      FROM  attr_set a
            JOIN config.record_attr_definition d ON (d.name = a.key AND d.filter AND a.value IS NOT NULL)
            LEFT JOIN config.coded_value_map m ON (m.ctype = a.key)
      WHERE m.id IS NULL;

-- Now construct the record-specific vector from the SVF data
INSERT INTO metabib.record_attr_vector_list (source,vlist)
    SELECT  a.id, ARRAY_AGG(COALESCE(u.id, c.id))
      FROM  metabib.record_attr a
            JOIN attr_set ON (a.id = attr_set.source)
            LEFT JOIN metabib.uncontrolled_record_attr_value u ON (u.attr = attr_set.key AND u.value = attr_set.value)
            LEFT JOIN config.coded_value_map c ON (c.ctype = attr_set.key AND c.code = attr_set.value)
      WHERE COALESCE(u.id,c.id) IS NOT NULL
      GROUP BY 1;

DROP VIEW IF EXISTS reporter.classic_current_circ; 
DROP VIEW metabib.rec_descriptor;
DROP TABLE metabib.record_attr;

CREATE TYPE metabib.record_attr_type AS (
    id      BIGINT,
    attrs   HSTORE
);

CREATE TABLE config.composite_attr_entry_definition(
    coded_value INT  PRIMARY KEY NOT NULL REFERENCES config.coded_value_map (id) ON UPDATE CASCADE ON DELETE CASCADE,
    definition  TEXT NOT NULL -- JSON
);

CREATE OR REPLACE VIEW metabib.record_attr_id_map AS
    SELECT id, attr, value FROM metabib.uncontrolled_record_attr_value
        UNION
    SELECT  c.id, c.ctype AS attr, c.code AS value
      FROM  config.coded_value_map c
            JOIN config.record_attr_definition d ON (d.name = c.ctype AND NOT d.composite);

CREATE VIEW metabib.composite_attr_id_map AS
    SELECT  c.id, c.ctype AS attr, c.code AS value
      FROM  config.coded_value_map c
            JOIN config.record_attr_definition d ON (d.name = c.ctype AND d.composite);

CREATE OR REPLACE VIEW metabib.full_attr_id_map AS
    SELECT id, attr, value FROM metabib.record_attr_id_map
        UNION
    SELECT id, attr, value FROM metabib.composite_attr_id_map;


-- Back-compat view ... we're moving to an INTARRAY world
CREATE VIEW metabib.record_attr_flat AS
    SELECT  v.source AS id,
            m.attr,
            m.value
      FROM  metabib.full_attr_id_map m
            JOIN  metabib.record_attr_vector_list v ON ( m.id = ANY( v.vlist ) );

CREATE VIEW metabib.record_attr AS
    SELECT id, HSTORE( ARRAY_AGG( attr ), ARRAY_AGG( value ) ) AS attrs FROM metabib.record_attr_flat GROUP BY 1;

CREATE VIEW metabib.rec_descriptor AS
    SELECT  id,
            id AS record,
            (populate_record(NULL::metabib.rec_desc_type, attrs)).*
      FROM  metabib.record_attr;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_init () RETURNS BOOL AS $f$
    $_SHARED{metabib_compile_composite_attr_cache} = {}
        if ! exists $_SHARED{metabib_compile_composite_attr_cache};
    return exists $_SHARED{metabib_compile_composite_attr_cache};
$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_disable () RETURNS BOOL AS $f$
    delete $_SHARED{metabib_compile_composite_attr_cache};
    return ! exists $_SHARED{metabib_compile_composite_attr_cache};
$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_invalidate () RETURNS BOOL AS $f$
    SELECT metabib.compile_composite_attr_cache_disable() AND metabib.compile_composite_attr_cache_init();
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.composite_attr_def_cache_inval_tgr () RETURNS TRIGGER AS $f$
BEGIN
    PERFORM metabib.compile_composite_attr_cache_invalidate();
    RETURN NULL;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER ccraed_cache_inval_tgr AFTER INSERT OR UPDATE OR DELETE ON config.composite_attr_entry_definition FOR EACH STATEMENT EXECUTE PROCEDURE metabib.composite_attr_def_cache_inval_tgr();
    
CREATE OR REPLACE FUNCTION metabib.compile_composite_attr ( cattr_def TEXT ) RETURNS query_int AS $func$

    use JSON::XS;

    my $json = shift;
    my $def = decode_json($json);

    die("Composite attribute definition not supplied") unless $def;

    my $_cache = (exists $_SHARED{metabib_compile_composite_attr_cache}) ? 1 : 0;

    return $_SHARED{metabib_compile_composite_attr_cache}{$json}
        if ($_cache && $_SHARED{metabib_compile_composite_attr_cache}{$json});

    sub recurse {
        my $d = shift;
        my $j = '&';
        my @list;

        if (ref $d eq 'HASH') { # node or AND
            if (exists $d->{_attr}) { # it is a node
                my $plan = spi_prepare('SELECT * FROM metabib.full_attr_id_map WHERE attr = $1 AND value = $2', qw/TEXT TEXT/);
                my $id = spi_exec_prepared(
                    $plan, {limit => 1}, $d->{_attr}, $d->{_val}
                )->{rows}[0]{id};
                spi_freeplan($plan);
                return $id;
            } elsif (exists $d->{_not} && scalar(keys(%$d)) == 1) { # it is a NOT
                return '!' . recurse($$d{_not});
            } else { # an AND list
                @list = map { recurse($$d{$_}) } sort keys %$d;
            }
        } elsif (ref $d eq 'ARRAY') {
            $j = '|';
            @list = map { recurse($_) } @$d;
        }

        @list = grep { defined && $_ ne '' } @list;

        return '(' . join($j,@list) . ')' if @list;
        return '';
    }

    my $val = recurse($def) || undef;
    $_SHARED{metabib_compile_composite_attr_cache}{$json} = $val if $_cache;
    return $val;

$func$ IMMUTABLE LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr ( cattr_id INT ) RETURNS query_int AS $func$
    SELECT metabib.compile_composite_attr(definition) FROM config.composite_attr_entry_definition WHERE coded_value = $1;
$func$ STRICT IMMUTABLE LANGUAGE SQL;


CREATE OR REPLACE FUNCTION public.oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
    temp_vector     TEXT := '';
    ts_rec          RECORD;
    cur_weight      "char";
BEGIN

    value := NEW.value;
    NEW.index_vector = ''::tsvector;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;

        NEW.value = value;

        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
   END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN

        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
        value := public.search_normalize(value);
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);

    ELSIF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR ts_rec IN

            SELECT DISTINCT m.ts_config, m.index_weight
            FROM config.metabib_class_ts_map m
                 LEFT JOIN metabib.record_attr_vector_list r ON (r.source = NEW.source)
                 LEFT JOIN config.coded_value_map ccvm ON (
                    ccvm.ctype IN ('item_lang', 'language') AND
                    ccvm.code = m.index_lang AND
                    r.vlist @> intset(ccvm.id)
                )
            WHERE m.field_class = TG_ARGV[0]
                AND m.active
                AND (m.always OR NOT EXISTS (SELECT 1 FROM config.metabib_field_ts_map WHERE metabib_field = NEW.field))
                AND (m.index_lang IS NULL OR ccvm.id IS NOT NULL)
                        UNION
            SELECT DISTINCT m.ts_config, m.index_weight
            FROM config.metabib_field_ts_map m
                 LEFT JOIN metabib.record_attr_vector_list r ON (r.source = NEW.source)
                 LEFT JOIN config.coded_value_map ccvm ON (
                    ccvm.ctype IN ('item_lang', 'language') AND
                    ccvm.code = m.index_lang AND
                    r.vlist @> intset(ccvm.id)
                )
            WHERE m.metabib_field = NEW.field
                AND m.active
                AND (m.index_lang IS NULL OR ccvm.id IS NOT NULL)
            ORDER BY index_weight ASC

        LOOP

            IF cur_weight IS NOT NULL AND cur_weight != ts_rec.index_weight THEN
                NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
                temp_vector = '';
            END IF;

            cur_weight = ts_rec.index_weight;
            SELECT INTO temp_vector temp_vector || ' ' || to_tsvector(ts_rec.ts_config::regconfig, value)::TEXT;

        END LOOP;
        NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
    ELSE
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- add new sr_format attribute definition

INSERT INTO config.record_attr_definition (name, label, phys_char_sf)
VALUES (
    'sr_format', 
    oils_i18n_gettext('sr_format', 'Sound recording format', 'crad', 'label'),
    '62'
);

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(557, 'sr_format', 'a', oils_i18n_gettext(557, '16 rpm', 'ccvm', 'value')),
(558, 'sr_format', 'b', oils_i18n_gettext(558, '33 1/3 rpm', 'ccvm', 'value')),
(559, 'sr_format', 'c', oils_i18n_gettext(559, '45 rpm', 'ccvm', 'value')),
(560, 'sr_format', 'f', oils_i18n_gettext(560, '1.4 m. per second', 'ccvm', 'value')),
(561, 'sr_format', 'd', oils_i18n_gettext(561, '78 rpm', 'ccvm', 'value')),
(562, 'sr_format', 'e', oils_i18n_gettext(562, '8 rpm', 'ccvm', 'value')),
(563, 'sr_format', 'l', oils_i18n_gettext(563, '1 7/8 ips', 'ccvm', 'value')),
(586, 'item_form', 'o', oils_i18n_gettext('586', 'Online', 'ccvm', 'value')),
(587, 'item_form', 'q', oils_i18n_gettext('587', 'Direct electronic', 'ccvm', 'value'));

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(564, 'icon_format', 'book', 
    oils_i18n_gettext(564, 'Book', 'ccvm', 'value'),
    oils_i18n_gettext(564, 'Book', 'ccvm', 'search_label')),
(565, 'icon_format', 'braille', 
    oils_i18n_gettext(565, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(565, 'Braille', 'ccvm', 'search_label')),
(566, 'icon_format', 'software', 
    oils_i18n_gettext(566, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(566, 'Software and video games', 'ccvm', 'search_label')),
(567, 'icon_format', 'dvd', 
    oils_i18n_gettext(567, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(567, 'DVD', 'ccvm', 'search_label')),
(568, 'icon_format', 'ebook', 
    oils_i18n_gettext(568, 'E-book', 'ccvm', 'value'),
    oils_i18n_gettext(568, 'E-book', 'ccvm', 'search_label')),
(569, 'icon_format', 'eaudio', 
    oils_i18n_gettext(569, 'E-audio', 'ccvm', 'value'),
    oils_i18n_gettext(569, 'E-audio', 'ccvm', 'search_label')),
(570, 'icon_format', 'kit', 
    oils_i18n_gettext(570, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(570, 'Kit', 'ccvm', 'search_label')),
(571, 'icon_format', 'map', 
    oils_i18n_gettext(571, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(571, 'Map', 'ccvm', 'search_label')),
(572, 'icon_format', 'microform', 
    oils_i18n_gettext(572, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(572, 'Microform', 'ccvm', 'search_label')),
(573, 'icon_format', 'score', 
    oils_i18n_gettext(573, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(573, 'Music Score', 'ccvm', 'search_label')),
(574, 'icon_format', 'picture', 
    oils_i18n_gettext(574, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(574, 'Picture', 'ccvm', 'search_label')),
(575, 'icon_format', 'equip', 
    oils_i18n_gettext(575, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(575, 'Equipment, games, toys', 'ccvm', 'search_label')),
(576, 'icon_format', 'serial', 
    oils_i18n_gettext(576, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(576, 'Serials and magazines', 'ccvm', 'search_label')),
(577, 'icon_format', 'vhs', 
    oils_i18n_gettext(577, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(577, 'VHS', 'ccvm', 'search_label')),
(578, 'icon_format', 'evideo', 
    oils_i18n_gettext(578, 'E-video', 'ccvm', 'value'),
    oils_i18n_gettext(578, 'E-video', 'ccvm', 'search_label')),
(579, 'icon_format', 'cdaudiobook', 
    oils_i18n_gettext(579, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(579, 'CD Audiobook', 'ccvm', 'search_label')),
(580, 'icon_format', 'cdmusic', 
    oils_i18n_gettext(580, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(580, 'CD Music recording', 'ccvm', 'search_label')),
(581, 'icon_format', 'casaudiobook', 
    oils_i18n_gettext(581, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(581, 'Cassette audiobook', 'ccvm', 'search_label')),
(582, 'icon_format', 'casmusic',
    oils_i18n_gettext(582, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(582, 'Audiocassette music recording', 'ccvm', 'search_label')),
(583, 'icon_format', 'phonospoken', 
    oils_i18n_gettext(583, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(583, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(584, 'icon_format', 'phonomusic', 
    oils_i18n_gettext(584, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(584, 'Phonograph music recording', 'ccvm', 'search_label')),
(585, 'icon_format', 'lpbook', 
    oils_i18n_gettext(585, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(585, 'Large Print Book', 'ccvm', 'search_label'))
;

-- add the new icon format attribute definition

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.icon_attr',
    oils_i18n_gettext(
        'opac.icon_attr', 
        'OPAC Format Icons Attribute',
        'cgf',
        'label'
    ),
    'icon_format', 
    TRUE
);

INSERT INTO config.record_attr_definition 
    (name, label, multi, filter, composite) VALUES (
    'icon_format',
    oils_i18n_gettext(
        'icon_format',
        'OPAC Format Icons',
        'crad',
        'label'
    ),
    TRUE, TRUE, TRUE
);

-- icon format composite definitions

INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES
--book
(564, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_not":[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"},{"_attr":"item_form","_val":"d"},{"_attr":"item_form","_val":"f"},{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"r"},{"_attr":"item_form","_val":"s"}]},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'),

-- braille
(565, '{"0":{"_attr":"item_type","_val":"a"},"1":{"_attr":"item_form","_val":"f"}}'),

-- software
(566, '{"_attr":"item_type","_val":"m"}'),

-- dvd
(567, '{"_attr":"vr_format","_val":"v"}'),

-- ebook
(568, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"q"}],"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'),

-- eaudio
(569, '{"0":{"_attr":"item_type","_val":"i"},"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"s"}]}'),

-- kit
(570, '[{"_attr":"item_type","_val":"o"},{"_attr":"item_type","_val":"p"}]'),

-- map
(571, '[{"_attr":"item_type","_val":"e"},{"_attr":"item_type","_val":"f"}]'),

-- microform
(572, '[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"}]'),

-- score
(573, '[{"_attr":"item_type","_val":"c"},{"_attr":"item_type","_val":"d"}]'),

-- picture
(574, '{"_attr":"item_type","_val":"k"}'),

-- equip
(575, '{"_attr":"item_type","_val":"r"}'),

-- serial
(576, '[{"_attr":"bib_level","_val":"b"},{"_attr":"bib_level","_val":"s"}]'),

-- vhs
(577, '{"_attr":"vr_format","_val":"b"}'),

-- evideo
(578, '{"0":{"_attr":"item_type","_val":"g"},"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"q"}]}'),

-- cdaudiobook
(579, '{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"sr_format","_val":"f"}}'),

-- cdmusic
(580, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_attr":"sr_format","_val":"f"}}'),

-- casaudiobook
(581, '{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"sr_format","_val":"l"}}'),

-- casmusic
(582, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_attr":"sr_format","_val":"l"}}'),

-- phonospoken
(583, '{"0":{"_attr":"item_type","_val":"i"},"1":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"e"}]}'),

-- phonomusic
(584, '{"0":{"_attr":"item_type","_val":"j"},"1":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"e"}]}'),

-- lpbook
(585, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_attr":"item_form","_val":"d"},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}');




CREATE OR REPLACE FUNCTION unapi.mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mra/' || $1 AS id, 
            'tag:open-ils.org:U2@bre/' || $1 AS record 
        ),  
        (SELECT XMLAGG(foo.y)
          FROM (
            SELECT  XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            mra.attr AS name,
                            cvm.value AS "coded-value",
                            cvm.id AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        mra.value
                    )
              FROM  metabib.record_attr_flat mra
                    JOIN config.record_attr_definition rad ON (mra.attr = rad.name)
                    LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = mra.attr AND code = mra.value)
              WHERE mra.id = $1
            )foo(y)
        )   
    )   
$F$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('0865', :eg_version);

-- First, explode the field into constituent parts
WITH format_parts_array AS (
    SELECT  a.id,
            STRING_TO_ARRAY(a.holdable_formats, '-') AS parts
      FROM  action.hold_request a
      WHERE a.hold_type = 'M'
            AND a.fulfillment_time IS NULL
), format_parts_wide AS (
    SELECT  id,
            regexp_split_to_array(parts[1], '') AS item_type,
            regexp_split_to_array(parts[2], '') AS item_form,
            parts[3] AS item_lang
      FROM  format_parts_array
), converted_formats_flat AS (
    SELECT  id, 
            CASE WHEN ARRAY_LENGTH(item_type,1) > 0
                THEN '"0":[{"_attr":"item_type","_val":"' || ARRAY_TO_STRING(item_type,'"},{"_attr":"item_type","_val":"') || '"}]'
                ELSE '"0":""'
            END AS item_type,
            CASE WHEN ARRAY_LENGTH(item_form,1) > 0
                THEN '"1":[{"_attr":"item_form","_val":"' || ARRAY_TO_STRING(item_form,'"},{"_attr":"item_form","_val":"') || '"}]'
                ELSE '"1":""'
            END AS item_form,
            CASE WHEN item_lang <> ''
                THEN '"2":[{"_attr":"item_lang","_val":"' || item_lang ||'"}]'
                ELSE '"2":""'
            END AS item_lang
      FROM  format_parts_wide
) UPDATE action.hold_request SET holdable_formats = '{' ||
        converted_formats_flat.item_type || ',' ||
        converted_formats_flat.item_form || ',' ||
        converted_formats_flat.item_lang || '}'
    FROM converted_formats_flat WHERE converted_formats_flat.id = action.hold_request.id;



SELECT evergreen.upgrade_deps_block_check('0866', :eg_version);

DROP FUNCTION asset.record_has_holdable_copy (BIGINT);
CREATE FUNCTION asset.record_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
        WHERE
            acn.record = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acp.circ_lib IN (SELECT id FROM actor.org_unit_descendants(COALESCE($2,(SELECT id FROM evergreen.org_top()))))
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.metarecord_has_holdable_copy (BIGINT);
CREATE FUNCTION asset.metarecord_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
            JOIN metabib.metarecord_source_map mmsm ON acn.record = mmsm.source
        WHERE
            mmsm.metarecord = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acp.circ_lib IN (SELECT id FROM actor.org_unit_descendants(COALESCE($2,(SELECT id FROM evergreen.org_top()))))
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM  
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.copy_id)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.copy_id)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;   
                
    RETURN;     
END;            
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE         
    ans RECORD; 
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.mmr_mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mmr/' || $1 AS metarecord
        ),
        (SELECT XMLAGG(foo.y)
          FROM (
            SELECT  DISTINCT ON (COALESCE(cvm.id,uvm.id))
                    COALESCE(cvm.id,uvm.id),
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            mra.attr AS name,
                            cvm.value AS "coded-value",
                            cvm.id AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        mra.value
                    )
              FROM  metabib.record_attr_flat mra
                    JOIN config.record_attr_definition rad ON (mra.attr = rad.name)
                    LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = mra.attr AND code = mra.value)
                    LEFT JOIN metabib.uncontrolled_record_attr_value uvm ON (uvm.attr = mra.attr AND uvm.value = mra.value)
              WHERE mra.id IN (
                    WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id 
                        FROM actor.org_unit WHERE shortname = $5 LIMIT 1)
                    SELECT source 
                    FROM metabib.metarecord_source_map, aou
                    WHERE metarecord = $1 AND (
                        EXISTS (
                            SELECT 1 FROM asset.opac_visible_copies 
                            WHERE record = source AND circ_lib IN (
                                SELECT id FROM actor.org_unit_descendants(aou.id, $6)) 
                            LIMIT 1
                        )
                        OR EXISTS (SELECT 1 FROM located_uris(source, aou.id, $10) LIMIT 1)
                    )
                )
              ORDER BY 1
            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[],
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, aou.name, acn.label_sortkey,
            evergreen.rank_ou(aou.id, $2, $6), evergreen.rank_cp_status(acp.status),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN actor.org_unit_descendants( $2, COALESCE(
                $3, (
                    SELECT depth
                    FROM actor.org_unit_type aout
                        INNER JOIN actor.org_unit ou ON ou_type = aout.id
                    WHERE ou.id = $2
                ), $6)
            ) AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN
                EXISTS (
                    SELECT 1
                    FROM asset.opac_visible_copies
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, acp.status, aou.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY evergreen.rank_ou(aou.id, $2, $6), evergreen.rank_cp_status(acp.status)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$
LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes
    ( bibid BIGINT, ouid INT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, pref_lib INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[] )
    RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT)
    AS $$ SELECT * FROM evergreen.ranked_volumes(ARRAY[$1],$2,$3,$4,$5,$6,$7) $$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION evergreen.located_uris (
    bibid BIGINT[],
    ouid INT,
    pref_lib INT DEFAULT NULL
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT) AS $$
    WITH all_orgs AS (SELECT COALESCE( enabled, FALSE ) AS flag FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy')
    SELECT DISTINCT ON (id) * FROM (
    SELECT acn.id, COALESCE(aou.name,aoud.name), acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( COALESCE($3, $2) ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( COALESCE($3, $2) ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR COALESCE(aou.id,aoud.id) IS NOT NULL)
    UNION
    SELECT acn.id, COALESCE(aou.name,aoud.name) AS name, acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( $2 ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( $2 ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR COALESCE(aou.id,aoud.id) IS NOT NULL))x
    ORDER BY id, pref_ou DESC;
$$
LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.located_uris ( bibid BIGINT, ouid INT, pref_lib INT DEFAULT NULL)
    RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT)
    AS $$ SELECT * FROM evergreen.located_uris(ARRAY[$1],$2,$3) $$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION unapi.mmr_holdings_xml (
    mid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('mmr' = ANY ($5)) THEN 'tag:open-ils.org:U2@mmr/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT metarecord_has_holdable_copy FROM asset.metarecord_has_holdable_copy($1)) AS has_holdable
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_metarecord_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_metarecord_copy_count($2, $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_metarecord_copy_count($9,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 -- XXX monograph_parts and foreign_copies are skipped in MRs ... put them back some day?
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes((SELECT ARRAY_AGG(source) FROM metabib.metarecord_source_map WHERE metarecord = $1), $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), uris.rank, name, label_sortkey
                        FROM evergreen.located_uris((SELECT ARRAY_AGG(source) FROM metabib.metarecord_source_map WHERE metarecord = $1), $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry IN (SELECT source FROM metabib.metarecord_source_map WHERE metarecord = $1)
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('0867', :eg_version);

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.metarecord.holds.format_attr', 
    oils_i18n_gettext(
        'opac.metarecord.holds.format_attr',
        'OPAC Metarecord Hold Formats Attribute', 
        'cgf',
        'label'
    ),
    'mr_hold_format', 
    TRUE
);

-- until we have a custom attribute for the selector, 
-- default to the icon_format attribute
INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.format_selector.attr', 
    oils_i18n_gettext(
        'opac.format_selector.attr', 
        'OPAC Format Selector Attribute', 
        'cgf',
        'label'
    ),
    'icon_format', 
    TRUE
);


INSERT INTO config.record_attr_definition 
    (name, label, multi, filter, composite) 
VALUES (
    'mr_hold_format', 
    oils_i18n_gettext(
        'mr_hold_format',
        'Metarecord Hold Formats', 
        'crad',
        'label'
    ),
    TRUE, TRUE, TRUE
);

-- these formats are a subset of the "icon_format" attribute,
-- modified to exclude electronic resources, which are not holdable

-- for i18n purposes, these have to be listed individually
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(588, 'mr_hold_format', 'book', 
    oils_i18n_gettext(588, 'Book', 'ccvm', 'value'),
    oils_i18n_gettext(588, 'Book', 'ccvm', 'search_label')),
(589, 'mr_hold_format', 'braille', 
    oils_i18n_gettext(589, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(589, 'Braille', 'ccvm', 'search_label')),
(590, 'mr_hold_format', 'software', 
    oils_i18n_gettext(590, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(590, 'Software and video games', 'ccvm', 'search_label')),
(591, 'mr_hold_format', 'dvd', 
    oils_i18n_gettext(591, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(591, 'DVD', 'ccvm', 'search_label')),
(592, 'mr_hold_format', 'kit', 
    oils_i18n_gettext(592, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(592, 'Kit', 'ccvm', 'search_label')),
(593, 'mr_hold_format', 'map', 
    oils_i18n_gettext(593, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(593, 'Map', 'ccvm', 'search_label')),
(594, 'mr_hold_format', 'microform', 
    oils_i18n_gettext(594, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(594, 'Microform', 'ccvm', 'search_label')),
(595, 'mr_hold_format', 'score', 
    oils_i18n_gettext(595, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(595, 'Music Score', 'ccvm', 'search_label')),
(596, 'mr_hold_format', 'picture', 
    oils_i18n_gettext(596, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(596, 'Picture', 'ccvm', 'search_label')),
(597, 'mr_hold_format', 'equip', 
    oils_i18n_gettext(597, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(597, 'Equipment, games, toys', 'ccvm', 'search_label')),
(598, 'mr_hold_format', 'serial', 
    oils_i18n_gettext(598, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(598, 'Serials and magazines', 'ccvm', 'search_label')),
(599, 'mr_hold_format', 'vhs', 
    oils_i18n_gettext(599, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(599, 'VHS', 'ccvm', 'search_label')),
(600, 'mr_hold_format', 'cdaudiobook', 
    oils_i18n_gettext(600, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(600, 'CD Audiobook', 'ccvm', 'search_label')),
(601, 'mr_hold_format', 'cdmusic', 
    oils_i18n_gettext(601, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(601, 'CD Music recording', 'ccvm', 'search_label')),
(602, 'mr_hold_format', 'casaudiobook', 
    oils_i18n_gettext(602, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(602, 'Cassette audiobook', 'ccvm', 'search_label')),
(603, 'mr_hold_format', 'casmusic',
    oils_i18n_gettext(603, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(603, 'Audiocassette music recording', 'ccvm', 'search_label')),
(604, 'mr_hold_format', 'phonospoken', 
    oils_i18n_gettext(604, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(604, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(605, 'mr_hold_format', 'phonomusic', 
    oils_i18n_gettext(605, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(605, 'Phonograph music recording', 'ccvm', 'search_label')),
(606, 'mr_hold_format', 'lpbook', 
    oils_i18n_gettext(606, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(606, 'Large Print Book', 'ccvm', 'search_label'))
;

-- but we can auto-generate the composite definitions

DO $$
    DECLARE format TEXT;
BEGIN
    FOR format IN SELECT UNNEST(
        '{book,braille,software,dvd,kit,map,microform,score,picture,equip,serial,vhs,cdaudiobook,cdmusic,casaudiobook,casmusic,phonospoken,phonomusic,lpbook}'::text[]) LOOP

        INSERT INTO config.composite_attr_entry_definition 
            (coded_value, definition) VALUES
            (
                -- get the ID from the new ccvm above
                (SELECT id FROM config.coded_value_map 
                    WHERE code = format AND ctype = 'mr_hold_format'),
                -- get the def of the matching ccvm attached to the icon_format attr
                (SELECT definition FROM config.composite_attr_entry_definition ccaed
                    JOIN config.coded_value_map ccvm ON (ccaed.coded_value = ccvm.id)
                    WHERE ccvm.ctype = 'icon_format' AND ccvm.code = format)
            );
    END LOOP; 
END $$;

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(607, 'icon_format', 'music', 
    oils_i18n_gettext(607, 'Musical Sound Recording (Unknown Format)', 'ccvm', 'value'),
    oils_i18n_gettext(607, 'Musical Sound Recording (Unknown Format)', 'ccvm', 'search_label'));

INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES
(607, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_not":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"f"},{"_attr":"sr_format","_val":"e"},{"_attr":"sr_format","_val":"l"}]}}');

-- icon for blu-ray
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(608, 'icon_format', 'blu-ray', 
    oils_i18n_gettext(608, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(608, 'Blu-ray', 'ccvm', 'search_label'));
INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES (608, '{"_attr":"vr_format","_val":"s"}');

-- metarecord hold format for blu-ray
INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(609, 'mr_hold_format', 'blu-ray', 
    oils_i18n_gettext(609, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(609, 'Blu-ray', 'ccvm', 'search_label'));
INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES (609, '{"_attr":"vr_format","_val":"s"}');



SELECT evergreen.upgrade_deps_block_check('0869', :eg_version);

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity_update () RETURNS TRIGGER AS $f$
BEGIN
    NEW.proximity := action.hold_copy_calculated_proximity(NEW.hold,NEW.target_copy);
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_copy_proximity_update_tgr BEFORE INSERT OR UPDATE ON action.hold_copy_map FOR EACH ROW EXECUTE PROCEDURE action.hold_copy_calculated_proximity_update ();

-- Now, cause the update we need in a HOT-friendly manner (http://pgsql.tapoueh.org/site/html/misc/hot.html)
UPDATE action.hold_copy_map SET proximity = proximity WHERE proximity IS NULL;


/*
 * Copyright (C) 2014  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */



SELECT evergreen.upgrade_deps_block_check('0870', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.located_uris (
    bibid BIGINT[],
    ouid INT,
    pref_lib INT DEFAULT NULL
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT) AS $$
    WITH all_orgs AS (SELECT COALESCE( enabled, FALSE ) AS flag FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy')
    SELECT DISTINCT ON (id) * FROM (
    SELECT acn.id, COALESCE(aou.name,aoud.name), acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( COALESCE($3, $2) ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( COALESCE($3, $2) ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR (all_orgs.flag AND COALESCE(aou.id,aoud.id) IS NOT NULL))
    UNION
    SELECT acn.id, COALESCE(aou.name,aoud.name) AS name, acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           LEFT JOIN actor.org_unit_ancestors( $2 ) aou ON (acn.owning_lib = aou.id)
           LEFT JOIN actor.org_unit_descendants( $2 ) aoud ON (acn.owning_lib = aoud.id),
           all_orgs
      WHERE acn.record = ANY ($1)
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
          AND ((NOT all_orgs.flag AND aou.id IS NOT NULL) OR (all_orgs.flag AND COALESCE(aou.id,aoud.id) IS NOT NULL)))x
    ORDER BY id, pref_ou DESC;
$$
LANGUAGE SQL STABLE;




SELECT evergreen.upgrade_deps_block_check('0871', :eg_version);

INSERT INTO config.record_attr_definition 
    (name, label, multi, filter, composite) VALUES (
        'search_format', 
        oils_i18n_gettext('search_format', 'Search Formats', 'crad', 'label'),
        TRUE, TRUE, TRUE
    );

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(610, 'search_format', 'book', 
    oils_i18n_gettext(610, 'All Books', 'ccvm', 'value'),
    oils_i18n_gettext(610, 'All Books', 'ccvm', 'search_label')),
(611, 'search_format', 'braille', 
    oils_i18n_gettext(611, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(611, 'Braille', 'ccvm', 'search_label')),
(612, 'search_format', 'software', 
    oils_i18n_gettext(612, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(612, 'Software and video games', 'ccvm', 'search_label')),
(613, 'search_format', 'dvd', 
    oils_i18n_gettext(613, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(613, 'DVD', 'ccvm', 'search_label')),
(614, 'search_format', 'ebook', 
    oils_i18n_gettext(614, 'E-book', 'ccvm', 'value'),
    oils_i18n_gettext(614, 'E-book', 'ccvm', 'search_label')),
(615, 'search_format', 'eaudio', 
    oils_i18n_gettext(615, 'E-audio', 'ccvm', 'value'),
    oils_i18n_gettext(615, 'E-audio', 'ccvm', 'search_label')),
(616, 'search_format', 'kit', 
    oils_i18n_gettext(616, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(616, 'Kit', 'ccvm', 'search_label')),
(617, 'search_format', 'map', 
    oils_i18n_gettext(617, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(617, 'Map', 'ccvm', 'search_label')),
(618, 'search_format', 'microform', 
    oils_i18n_gettext(618, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(618, 'Microform', 'ccvm', 'search_label')),
(619, 'search_format', 'score', 
    oils_i18n_gettext(619, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(619, 'Music Score', 'ccvm', 'search_label')),
(620, 'search_format', 'picture', 
    oils_i18n_gettext(620, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(620, 'Picture', 'ccvm', 'search_label')),
(621, 'search_format', 'equip', 
    oils_i18n_gettext(621, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(621, 'Equipment, games, toys', 'ccvm', 'search_label')),
(622, 'search_format', 'serial', 
    oils_i18n_gettext(622, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(622, 'Serials and magazines', 'ccvm', 'search_label')),
(623, 'search_format', 'vhs', 
    oils_i18n_gettext(623, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(623, 'VHS', 'ccvm', 'search_label')),
(624, 'search_format', 'evideo', 
    oils_i18n_gettext(624, 'E-video', 'ccvm', 'value'),
    oils_i18n_gettext(624, 'E-video', 'ccvm', 'search_label')),
(625, 'search_format', 'cdaudiobook', 
    oils_i18n_gettext(625, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(625, 'CD Audiobook', 'ccvm', 'search_label')),
(626, 'search_format', 'cdmusic', 
    oils_i18n_gettext(626, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(626, 'CD Music recording', 'ccvm', 'search_label')),
(627, 'search_format', 'casaudiobook', 
    oils_i18n_gettext(627, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(627, 'Cassette audiobook', 'ccvm', 'search_label')),
(628, 'search_format', 'casmusic',
    oils_i18n_gettext(628, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(628, 'Audiocassette music recording', 'ccvm', 'search_label')),
(629, 'search_format', 'phonospoken', 
    oils_i18n_gettext(629, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(629, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(630, 'search_format', 'phonomusic', 
    oils_i18n_gettext(630, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(630, 'Phonograph music recording', 'ccvm', 'search_label')),
(631, 'search_format', 'lpbook', 
    oils_i18n_gettext(631, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(631, 'Large Print Book', 'ccvm', 'search_label')),
(632, 'search_format', 'music', 
    oils_i18n_gettext(632, 'All Music', 'ccvm', 'label'),
    oils_i18n_gettext(632, 'All Music', 'ccvm', 'search_label')),
(633, 'search_format', 'blu-ray', 
    oils_i18n_gettext(633, 'Blu-ray', 'ccvm', 'value'),
    oils_i18n_gettext(633, 'Blu-ray', 'ccvm', 'search_label'));



-- copy the composite definition from icon_format into 
-- search_format for a baseline data set
DO $$
    DECLARE format config.coded_value_map%ROWTYPE;
BEGIN
    FOR format IN SELECT * 
        FROM config.coded_value_map WHERE ctype = 'icon_format'
    LOOP
        INSERT INTO config.composite_attr_entry_definition 
            (coded_value, definition) VALUES
            (
                -- get the ID from the new ccvm above
                (SELECT id FROM config.coded_value_map 
                    WHERE code = format.code AND ctype = 'search_format'),

                -- def of the matching icon_format attr
                (SELECT definition FROM config.composite_attr_entry_definition 
                    WHERE coded_value = format.id)
            );
    END LOOP; 
END $$;

-- modify the 'book' definition so that it includes large print
UPDATE config.composite_attr_entry_definition 
    SET definition = '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_not":[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"},{"_attr":"item_form","_val":"f"},{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"r"},{"_attr":"item_form","_val":"s"}]},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'
    WHERE coded_value = 610;

-- modify 'music' to include all recorded music, regardless of format
UPDATE config.composite_attr_entry_definition 
    SET definition = '{"_attr":"item_type","_val":"j"}'
    WHERE coded_value = 632;

UPDATE config.global_flag 
    SET value = 'search_format' 
    WHERE name = 'opac.format_selector.attr';



SELECT evergreen.upgrade_deps_block_check('0872', :eg_version);

CREATE OR REPLACE FUNCTION metabib.remap_metarecord_for_bib( bib_id BIGINT, fp TEXT, bib_is_deleted BOOL DEFAULT FALSE, retain_deleted BOOL DEFAULT FALSE ) RETURNS BIGINT AS $func$
DECLARE
    new_mapping     BOOL := TRUE;
    source_count    INT;
    old_mr          BIGINT;
    tmp_mr          metabib.metarecord%ROWTYPE;
    deleted_mrs     BIGINT[];
BEGIN

    -- We need to make sure we're not a deleted master record of an MR
    IF bib_is_deleted THEN
        FOR old_mr IN SELECT id FROM metabib.metarecord WHERE master_record = bib_id LOOP

            IF NOT retain_deleted THEN -- Go away for any MR that we're master of, unless retained
                DELETE FROM metabib.metarecord_source_map WHERE source = bib_id;
            END IF;

            -- Now, are there any more sources on this MR?
            SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = old_mr;

            IF source_count = 0 AND NOT retain_deleted THEN -- No other records
                deleted_mrs := ARRAY_APPEND(deleted_mrs, old_mr); -- Just in case...
                DELETE FROM metabib.metarecord WHERE id = old_mr;

            ELSE -- indeed there are. Update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC LIMIT 1)
                  WHERE id = old_mr;
            END IF;
        END LOOP;

    ELSE -- insert or update

        FOR tmp_mr IN SELECT m.* FROM metabib.metarecord m JOIN metabib.metarecord_source_map s ON (s.metarecord = m.id) WHERE s.source = bib_id LOOP

            -- Find the first fingerprint-matching
            IF old_mr IS NULL AND fp = tmp_mr.fingerprint THEN
                old_mr := tmp_mr.id;
                new_mapping := FALSE;

            ELSE -- Our fingerprint changed ... maybe remove the old MR
                DELETE FROM metabib.metarecord_source_map WHERE metarecord = old_mr AND source = bib_id; -- remove the old source mapping
                SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id;
                IF source_count = 0 THEN -- No other records
                    deleted_mrs := ARRAY_APPEND(deleted_mrs, tmp_mr.id);
                    DELETE FROM metabib.metarecord WHERE id = tmp_mr.id;
                END IF;
            END IF;

        END LOOP;

        -- we found no suitable, preexisting MR based on old source maps
        IF old_mr IS NULL THEN
            SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp; -- is there one for our current fingerprint?

            IF old_mr IS NULL THEN -- nope, create one and grab its id
                INSERT INTO metabib.metarecord ( fingerprint, master_record ) VALUES ( fp, bib_id );
                SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp;

            ELSE -- indeed there is. update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC LIMIT 1)
                  WHERE id = old_mr;
            END IF;

        ELSE -- there was one we already attached to, update its mods cache and master_record
            UPDATE  metabib.metarecord
              SET   mods = NULL,
                    master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC LIMIT 1)
              WHERE id = old_mr;
        END IF;

        IF new_mapping THEN
            INSERT INTO metabib.metarecord_source_map (metarecord, source) VALUES (old_mr, bib_id); -- new source mapping
        END IF;

    END IF;

    IF ARRAY_UPPER(deleted_mrs,1) > 0 THEN
        UPDATE action.hold_request SET target = old_mr WHERE target IN ( SELECT unnest(deleted_mrs) ) AND hold_type = 'M'; -- if we had to delete any MRs above, make sure their holds are moved
    END IF;

    RETURN old_mr;

END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION metabib.remap_metarecord_for_bib( bib_id BIGINT, fp TEXT );

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    tmp_bool BOOL;
BEGIN

    IF NEW.deleted THEN -- If this bib is deleted

        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;

        tmp_bool := FOUND; -- Just in case this is changed by some other statement

        PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint, TRUE, tmp_bool );

        IF NOT tmp_bool THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.record_attr_vector_list WHERE source = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.reingest_record_attributes(NEW.id, NULL, NEW.marc, TG_OP = 'INSERT' OR OLD.deleted);
        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.mmr (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
DECLARE
    mmrec   metabib.metarecord%ROWTYPE;
    leadrec biblio.record_entry%ROWTYPE;
    subrec biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    xml_buf TEXT; -- growing XML document
    tmp_xml TEXT; -- single-use XML string
    xml_frag TEXT; -- single-use XML fragment
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
    subxml  XML; -- subordinate records elements
    sub_xpath TEXT; 
    parts   TEXT[]; 
BEGIN

    -- xpath for extracting bre.marc values from subordinate records 
    -- so they may be appended to the MARC of the master record prior
    -- to XSLT processing.
    -- subjects, isbn, issn, upc -- anything else?
    sub_xpath := 
      '//*[starts-with(@tag, "6") or @tag="020" or @tag="022" or @tag="024"]';

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT INTO mmrec * FROM metabib.metarecord WHERE id = obj_id;
    IF NOT FOUND THEN
        RETURN NULL::XML;
    END IF;

    -- TODO: aggregate holdings from constituent records
    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.mmr_holdings_xml(
            obj_id, ouid, org, depth,
            evergreen.array_remove_item_by_value(includes,'holdings_xml'),
            slimit, soffset, include_xmlns, pref_lib);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT INTO leadrec * FROM biblio.record_entry WHERE id = mmrec.master_record;

    -- Grab distinct MVF for all records if requested
    IF ('mra' = ANY (includes)) THEN 
        axml := unapi.mmr_mra(obj_id,NULL,NULL,NULL,org,depth,NULL,NULL,TRUE,pref_lib);
    ELSE
        axml := NULL::XML;
    END IF;

    xml_buf = leadrec.marc;

    hxml := NULL::XML;
    IF ('holdings_xml' = ANY (includes)) THEN
        hxml := unapi.mmr_holdings_xml(
                    obj_id, ouid, org, depth,
                    evergreen.array_remove_item_by_value(includes,'holdings_xml'),
                    slimit, soffset, include_xmlns, pref_lib);
    END IF;

    subxml := NULL::XML;
    parts := '{}'::TEXT[];
    FOR subrec IN SELECT bre.* FROM biblio.record_entry bre
         JOIN metabib.metarecord_source_map mmsm ON (mmsm.source = bre.id)
         JOIN metabib.metarecord mmr ON (mmr.id = mmsm.metarecord)
         WHERE mmr.id = obj_id AND NOT bre.deleted
         ORDER BY CASE WHEN bre.id = mmr.master_record THEN 0 ELSE bre.id END
         LIMIT COALESCE((slimit->'bre')::INT, 5) LOOP

        IF subrec.id = leadrec.id THEN CONTINUE; END IF;
        -- Append choice data from the the non-lead records to the 
        -- the lead record document

        parts := parts || xpath(sub_xpath, subrec.marc::XML)::TEXT[];
    END LOOP;

    SELECT ARRAY_TO_STRING( ARRAY_AGG( DISTINCT p ), '' )::XML INTO subxml FROM UNNEST(parts) p;

    -- append data from the subordinate records to the 
    -- main record document before applying the XSLT

    IF subxml IS NOT NULL THEN 
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</record>(.*?)$', subxml || '</record>' || E'\\1');
    END IF;

    IF format = 'marcxml' THEN
         -- If we're not using the prefixed namespace in 
         -- this record, then remove all declarations of it
        IF xml_buf !~ E'<marc:' THEN
           xml_buf := REGEXP_REPLACE(xml_buf, 
            ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF; 
    ELSE
        xml_buf := oils_xslt_process(xml_buf, xfrm.xslt)::XML;
    END IF;

    -- update top_el to reflect the change in xml_buf, which may
    -- now be a different type of document (e.g. record -> mods)
    top_el := REGEXP_REPLACE(xml_buf, E'^.*?<((?:\\S+:)?' || 
        layout.holdings_element || ').*$', E'\\1');

    IF axml IS NOT NULL THEN 
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

    IF hxml IS NOT NULL THEN
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('mmr.unapi' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            xml_buf,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@mmr/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := xml_buf;
    END IF;

    -- remove ignorable whitesace
    output := REGEXP_REPLACE(output::TEXT,E'>\\s+<','><','gs')::XML;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL STABLE;

-- Forcibly remap deleted master records, retaining the linkage if so configured.
SELECT  count(metabib.remap_metarecord_for_bib( bre.id, bre.fingerprint, TRUE, COALESCE(flag.enabled,FALSE)))
  FROM  metabib.metarecord metar
        JOIN biblio.record_entry bre ON bre.id = metar.master_record,
        config.internal_flag flag
  WHERE bre.deleted = TRUE AND flag.name = 'ingest.metarecord_mapping.preserve_on_delete';



SELECT evergreen.upgrade_deps_block_check('0873', :eg_version);

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint(pickup_ou integer, request_ou integer, match_item bigint, match_user integer, match_requestor integer)
  RETURNS integer AS
$func$
DECLARE
    requestor_object    actor.usr%ROWTYPE;
    user_object         actor.usr%ROWTYPE;
    item_object         asset.copy%ROWTYPE;
    item_cn_object      asset.call_number%ROWTYPE;
    my_item_age         INTERVAL;
    rec_descriptor      metabib.rec_descriptor%ROWTYPE;
    matchpoint          config.hold_matrix_matchpoint%ROWTYPE;
    weights             config.hold_matrix_weights%ROWTYPE;
    denominator         NUMERIC(6,2);
    v_pickup_ou         ALIAS FOR pickup_ou;
    v_request_ou         ALIAS FOR request_ou;
BEGIN
    SELECT INTO user_object         * FROM actor.usr                WHERE id = match_user;
    SELECT INTO requestor_object    * FROM actor.usr                WHERE id = match_requestor;
    SELECT INTO item_object         * FROM asset.copy               WHERE id = match_item;
    SELECT INTO item_cn_object      * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor      * FROM metabib.rec_descriptor   WHERE record = item_cn_object.record;

    SELECT INTO my_item_age age(coalesce(item_object.active_date, now()));

    -- The item's owner should probably be the one determining if the item is holdable
    -- How to decide that is debatable. Decided to default to the circ library (where the item lives)
    -- This flag will allow for setting it to the owning library (where the call number "lives")
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.weight_owner_not_circ' AND enabled;

    -- Grab the closest set circ weight setting.
    IF NOT FOUND THEN
        -- Default to circ library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    ELSE
        -- Flag is set, use owning library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    END IF;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.user_home_ou    := 5.0;
        weights.request_ou      := 5.0;
        weights.pickup_ou       := 5.0;
        weights.item_owning_ou  := 5.0;
        weights.item_circ_ou    := 5.0;
        weights.usr_grp         := 7.0;
        weights.requestor_grp   := 8.0;
        weights.circ_modifier   := 4.0;
        weights.marc_type       := 3.0;
        weights.marc_form       := 2.0;
        weights.marc_bib_level  := 1.0;
        weights.marc_vr_format  := 1.0;
        weights.juvenile_flag   := 4.0;
        weights.ref_flag        := 0.0;
        weights.item_age        := 0.0;
    END IF;

    -- Determine the max (expected) depth (+1) of the org tree and max depth of the permisson tree
    -- If you break your org tree with funky parenting this may be wrong
    -- Note: This CTE is duplicated in the find_circ_matrix_matchpoint function, and it may be a good idea to split it off to a function
    -- We use one denominator for all tree-based checks for when permission groups and org units have the same weighting
    WITH all_distance(distance) AS (
            SELECT depth AS distance FROM actor.org_unit_type
        UNION
            SELECT distance AS distance FROM permission.grp_ancestors_distance((SELECT id FROM permission.grp_tree WHERE parent IS NULL))
	)
    SELECT INTO denominator MAX(distance) + 1 FROM all_distance;

    -- To ATTEMPT to make this work like it used to, make it reverse the user/requestor profile ids.
    -- This may be better implemented as part of the upgrade script?
    -- Set usr_grp = requestor_grp, requestor_grp = 1 or something when this flag is already set
    -- Then remove this flag, of course.
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.usr_not_requestor' AND enabled;

    IF FOUND THEN
        -- Note: This, to me, is REALLY hacky. I put it in anyway.
        -- If you can't tell, this is a single call swap on two variables.
        SELECT INTO user_object.profile, requestor_object.profile
                    requestor_object.profile, user_object.profile;
    END IF;

    -- Select the winning matchpoint into the matchpoint variable for returning
    SELECT INTO matchpoint m.*
      FROM  config.hold_matrix_matchpoint m
            /*LEFT*/ JOIN permission.grp_ancestors_distance( requestor_object.profile ) rpgad ON m.requestor_grp = rpgad.id
            LEFT JOIN permission.grp_ancestors_distance( user_object.profile ) upgad ON m.usr_grp = upgad.id
            LEFT JOIN actor.org_unit_ancestors_distance( v_pickup_ou ) puoua ON m.pickup_ou = puoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( v_request_ou ) rqoua ON m.request_ou = rqoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) cnoua ON m.item_owning_ou = cnoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.item_circ_ou = iooua.id
            LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
      WHERE m.active
            -- Permission Groups
         -- AND (m.requestor_grp        IS NULL OR upgad.id IS NOT NULL) -- Optional Requestor Group?
            AND (m.usr_grp              IS NULL OR upgad.id IS NOT NULL)
            -- Org Units
            AND (m.pickup_ou            IS NULL OR (puoua.id IS NOT NULL AND (puoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.request_ou           IS NULL OR (rqoua.id IS NOT NULL AND (rqoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_owning_ou       IS NULL OR (cnoua.id IS NOT NULL AND (cnoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_circ_ou         IS NULL OR (iooua.id IS NOT NULL AND (iooua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.user_home_ou         IS NULL OR (uhoua.id IS NOT NULL AND (uhoua.distance = 0 OR NOT m.strict_ou_match)))
            -- Static User Checks
            AND (m.juvenile_flag        IS NULL OR m.juvenile_flag = user_object.juvenile)
            -- Static Item Checks
            AND (m.circ_modifier        IS NULL OR m.circ_modifier = item_object.circ_modifier)
            AND (m.marc_type            IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
            AND (m.marc_form            IS NULL OR m.marc_form = rec_descriptor.item_form)
            AND (m.marc_bib_level       IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
            AND (m.marc_vr_format       IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
            AND (m.ref_flag             IS NULL OR m.ref_flag = item_object.ref)
            AND (m.item_age             IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
      ORDER BY
            -- Permission Groups
            CASE WHEN rpgad.distance    IS NOT NULL THEN 2^(2*weights.requestor_grp - (rpgad.distance/denominator)) ELSE 0.0 END +
            CASE WHEN upgad.distance    IS NOT NULL THEN 2^(2*weights.usr_grp - (upgad.distance/denominator)) ELSE 0.0 END +
            -- Org Units
            CASE WHEN puoua.distance    IS NOT NULL THEN 2^(2*weights.pickup_ou - (puoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN rqoua.distance    IS NOT NULL THEN 2^(2*weights.request_ou - (rqoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN cnoua.distance    IS NOT NULL THEN 2^(2*weights.item_owning_ou - (cnoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN iooua.distance    IS NOT NULL THEN 2^(2*weights.item_circ_ou - (iooua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN uhoua.distance    IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
            -- Static User Checks       -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.juvenile_flag   IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier   IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
            CASE WHEN m.marc_type       IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
            CASE WHEN m.marc_form       IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
            CASE WHEN m.marc_vr_format  IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
            CASE WHEN m.ref_flag        IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END +
            -- Item age has a slight adjustment to weight based on value.
            -- This should ensure that a shorter age limit comes first when all else is equal.
            -- NOTE: This assumes that intervals will normally be in days.
            CASE WHEN m.item_age            IS NOT NULL THEN 4^weights.item_age - 86400/EXTRACT(EPOCH FROM m.item_age) ELSE 0.0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return just the ID for now
    RETURN matchpoint.id;
END;
$func$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object     asset.call_number%ROWTYPE;
    item_status_object  config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
    hold_penalty TEXT;
    v_pickup_ou ALIAS FOR pickup_ou;
    v_request_ou ALIAS FOR request_ou;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( v_pickup_ou );

    result.success := TRUE;

    -- The HOLD penalty block only applies to new holds.
    -- The CAPTURE penalty block applies to existing holds.
    hold_penalty := 'HOLD';
    IF retargetting THEN
        hold_penalty := 'CAPTURE';
    END IF;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(v_pickup_ou, v_request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO item_status_object * FROM config.copy_status WHERE id = item_object.status;
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_object.holdable IS FALSE THEN
        result.fail_part := 'item.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_status_object.holdable IS FALSE THEN
        result.fail_part := 'status.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_location_object.holdable IS FALSE THEN
        result.fail_part := 'location.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = v_pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;
 
    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE '%' || hold_penalty || '%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP
    
            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_cn_object.owning_lib);
        ELSE
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_object.circ_lib);
        END IF;
        IF use_active_date = 'true' THEN
            age_protect_date := COALESCE(item_object.active_date, NOW());
        ELSE
            age_protect_date := item_object.create_date;
        END IF;
        IF age_protect_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = v_pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = v_pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;



SELECT evergreen.upgrade_deps_block_check('0874', :eg_version);

DROP FUNCTION IF EXISTS evergreen.oils_xpath( TEXT, TEXT, ANYARRAY);
DROP FUNCTION IF EXISTS public.oils_xpath(TEXT, TEXT, ANYARRAY);
DROP FUNCTION IF EXISTS public.oils_xpath(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.oils_xslt_process(TEXT, TEXT);

CREATE OR REPLACE FUNCTION evergreen.xml_famous5_to_text( TEXT ) RETURNS TEXT AS $f$
 SELECT REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE( $1, '&lt;', '<'),
                        '&gt;',
                        '>'
                    ),
                    '&apos;',
                    $$'$$
                ), -- ' ... vim
                '&quot;',
                '"'
            ),
            '&amp;',
            '&'
        );
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.oils_xpath ( TEXT, TEXT, TEXT[] ) RETURNS TEXT[] AS $f$
    SELECT  ARRAY_AGG(
                CASE WHEN strpos(x,'<') = 1 THEN -- It's an element node
                    x
                ELSE -- it's text-ish
                    evergreen.xml_famous5_to_text(x)
                END
            )
      FROM  UNNEST(XPATH( $1, $2::XML, $3 )::TEXT[]) x;
$f$ LANGUAGE SQL IMMUTABLE;

-- Trust me, it's just simpler to duplicate these...
CREATE OR REPLACE FUNCTION evergreen.oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS $f$
    SELECT  ARRAY_AGG(
                CASE WHEN strpos(x,'<') = 1 THEN -- It's an element node
                    x
                ELSE -- it's text-ish
                    evergreen.xml_famous5_to_text(x)
                END
            )
      FROM  UNNEST(XPATH( $1, $2::XML)::TEXT[]) x;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $func$
  use strict;

  use XML::LibXSLT;
  use XML::LibXML;

  my $doc = shift;
  my $xslt = shift;

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new();

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  my $xslt_parser = $_SHARED{'_xslt_process'}{parsers}{xslt} || XML::LibXSLT->new();

  # Cache the XSLT processor, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xslt} = $xslt_parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xslt});

  my $stylesheet = $_SHARED{'_xslt_process'}{stylesheets}{$xslt} ||
    $xslt_parser->parse_stylesheet( $parser->parse_string($xslt) );

  $_SHARED{'_xslt_process'}{stylesheets}{$xslt} = $stylesheet
    unless ($_SHARED{'_xslt_process'}{stylesheets}{$xslt});

  return $stylesheet->output_string(
    $stylesheet->transform(
      $parser->parse_string($doc)
    )
  );

$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    joiner_text     TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT; 
BEGIN

    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN ( SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    res.record := auth_id;

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP

        res.atag := acsaf.id;
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        joiner_text := COALESCE(acsaf.joiner, ' ');

        FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)::TEXT[]) LOOP

            heading_text := COALESCE(
                oils_xpath_string('./*[contains("'||acsaf.display_sf_list||'",@code)]', tmp_xml, joiner_text),
                ''
            );

            IF nfi_used IS NOT NULL THEN

                sort_text := SUBSTRING(
                    heading_text FROM
                    COALESCE(
                        NULLIF(
                            REGEXP_REPLACE(
                                oils_xpath_string('./@ind'||nfi_used, tmp_xml::TEXT),
                                $$\D+$$,
                                '',
                                'g'
                            ),
                            ''
                        )::INT,
                        0
                    ) + 1
                );

            ELSE
                sort_text := heading_text;
            END IF;

            IF heading_text IS NOT NULL AND heading_text <> '' THEN
                res.value := heading_text;
                res.sort_value := public.naco_normalize(sort_text);
                res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                RETURN NEXT res;
            END IF;

        END LOOP;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION url_verify.extract_urls ( session_id INT, item_id INT ) RETURNS INT AS $$
DECLARE
    last_seen_tag TEXT;
    current_tag TEXT;
    current_sf TEXT;
    current_url TEXT;
    current_ord INT;
    current_url_pos INT;
    current_selector url_verify.url_selector%ROWTYPE;
BEGIN
    current_ord := 1;

    FOR current_selector IN SELECT * FROM url_verify.url_selector s WHERE s.session = session_id LOOP
        current_url_pos := 1;
        LOOP
            SELECT  (oils_xpath(current_selector.xpath || '/text()', b.marc))[current_url_pos] INTO current_url
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            EXIT WHEN current_url IS NULL;

            SELECT  (oils_xpath(current_selector.xpath || '/../@tag', b.marc))[current_url_pos] INTO current_tag
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            IF current_tag IS NULL THEN
                current_tag := last_seen_tag;
            ELSE
                last_seen_tag := current_tag;
            END IF;

            SELECT  (oils_xpath(current_selector.xpath || '/@code', b.marc))[current_url_pos] INTO current_sf
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            INSERT INTO url_verify.url (session, item, url_selector, tag, subfield, ord, full_url)
              VALUES ( session_id, item_id, current_selector.id, current_tag, current_sf, current_ord, current_url);

            current_url_pos := current_url_pos + 1;
            current_ord := current_ord + 1;
        END LOOP;
    END LOOP;

    RETURN current_ord - 1;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        joiner := COALESCE(idx.joiner, default_joiner);

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            -- XXX much of this should be moved into oils_xpath_string...
            curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                    REGEXP_REPLACE( xml_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                joiner
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.naco_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                -- Returning browse rows with search_field = true for search+browse
                -- configs allows us to retain granularity of being able to search
                -- browse fields with "starts with" type operators (for example, for
                -- titles of songs in music albums)
                IF idx.search_field THEN
                    output_row.search_field = TRUE;
                END IF;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
                output_row.search_field = FALSE;
                output_row.sort_value := NULL;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;

$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_record_attributes (rid BIGINT, pattr_list TEXT[] DEFAULT NULL, prmarc TEXT DEFAULT NULL, rdeleted BOOL DEFAULT TRUE) RETURNS VOID AS $func$
DECLARE
    transformed_xml TEXT;
    rmarc           TEXT := prmarc;
    tmp_val         TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_vector     INT[] := '{}'::INT[];
    attr_vector_tmp INT[];
    attr_list       TEXT[] := pattr_list;
    attr_value      TEXT[];
    norm_attr_value TEXT[];
    tmp_xml         TEXT;
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition;
    END IF;

    IF rmarc IS NULL THEN
        SELECT marc INTO rmarc FROM biblio.record_entry WHERE id = rid;
    END IF;

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE NOT composite AND name = ANY( attr_list ) ORDER BY format LOOP

        attr_value := '{}'::TEXT[];
        norm_attr_value := '{}'::TEXT[];
        attr_vector_tmp := '{}'::INT[];

        SELECT * INTO ccvm_row FROM config.coded_value_map c WHERE c.ctype = attr_def.name LIMIT 1; 

        -- tag+sf attrs only support SVF
        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY[ARRAY_TO_STRING(ARRAY_AGG(value), COALESCE(attr_def.joiner,' '))] INTO attr_value
              FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
              WHERE record = rid
                    AND tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL 
                            THEN POSITION(subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                    END
              GROUP BY tag
              ORDER BY tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field_list(rmarc, attr_def.fixed_field);

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
        
            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(rmarc,xfrm.xslt);
                ELSE
                    transformed_xml := rmarc;
                END IF;
    
                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            FOR tmp_xml IN SELECT oils_xpath(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml,
                                COALESCE(attr_def.joiner,' '),
                                ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                            );
                IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                    attr_value := attr_value || tmp_val;
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END LOOP;

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  ARRAY_AGG(m.value) INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(rmarc) v
                    LEFT JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf AND (m.value IS NOT NULL AND BTRIM(m.value) <> '')
                    AND ( ccvm_row.id IS NULL OR ( ccvm_row.id IS NOT NULL AND v.id IS NOT NULL) );

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        END IF;

                -- apply index normalizers to attr_value
        FOR tmp_val IN SELECT value FROM UNNEST(attr_value) x(value) LOOP
            FOR normalizer IN
                SELECT  n.func AS func,
                        n.param_count AS param_count,
                        m.params AS params
                  FROM  config.index_normalizer n
                        JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                  WHERE attr = attr_def.name
                  ORDER BY m.pos LOOP
                    EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    COALESCE( quote_literal( tmp_val ), 'NULL' ) ||
                        CASE
                            WHEN normalizer.param_count > 0
                                THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                ELSE ''
                            END ||
                    ')' INTO tmp_val;

            END LOOP;
            IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                norm_attr_value := norm_attr_value || tmp_val;
            END IF;
        END LOOP;
        
        IF attr_def.filter THEN
            -- Create unknown uncontrolled values and find the IDs of the values
            IF ccvm_row.id IS NULL THEN
                FOR tmp_val IN SELECT value FROM UNNEST(norm_attr_value) x(value) LOOP
                    IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                        BEGIN -- use subtransaction to isolate unique constraint violations
                            INSERT INTO metabib.uncontrolled_record_attr_value ( attr, value ) VALUES ( attr_def.name, tmp_val );
                        EXCEPTION WHEN unique_violation THEN END;
                    END IF;
                END LOOP;

                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM metabib.uncontrolled_record_attr_value WHERE attr = attr_def.name AND value = ANY( norm_attr_value );
            ELSE
                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM config.coded_value_map WHERE ctype = attr_def.name AND code = ANY( norm_attr_value );
            END IF;

            -- Add the new value to the vector
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

        IF attr_def.sorter AND norm_attr_value[1] IS NOT NULL THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
        END IF;

    END LOOP;

/* We may need to rewrite the vlist to contain
   the intersection of new values for requested
   attrs and old values for ignored attrs. To
   do this, we take the old attr vlist and
   subtract any values that are valid for the
   requested attrs, and then add back the new
   set of attr values. */

    IF ARRAY_LENGTH(pattr_list, 1) > 0 THEN 
        SELECT vlist INTO attr_vector_tmp FROM metabib.record_attr_vector_list WHERE source = rid;
        SELECT attr_vector_tmp - ARRAY_AGG(id::INT) INTO attr_vector_tmp FROM metabib.full_attr_id_map WHERE attr = ANY (pattr_list);
        attr_vector := attr_vector || attr_vector_tmp;
    END IF;

    -- On to composite attributes, now that the record attrs have been pulled.  Processed in name order, so later composite
    -- attributes can depend on earlier ones.
    PERFORM metabib.compile_composite_attr_cache_init();
    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE composite AND name = ANY( attr_list ) ORDER BY name LOOP

        FOR ccvm_row IN SELECT * FROM config.coded_value_map c WHERE c.ctype = attr_def.name ORDER BY value LOOP

            tmp_val := metabib.compile_composite_attr( ccvm_row.id );
            CONTINUE WHEN tmp_val IS NULL OR tmp_val = ''; -- nothing to do

            IF attr_def.filter THEN
                IF attr_vector @@ tmp_val::query_int THEN
                    attr_vector = attr_vector + intset(ccvm_row.id);
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END IF;

            IF attr_def.sorter THEN
                IF attr_vector @@ tmp_val THEN
                    DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
                    INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, ccvm_row.code);
                END IF;
            END IF;

        END LOOP;

    END LOOP;

    IF ARRAY_LENGTH(attr_vector, 1) > 0 THEN
        IF rdeleted THEN -- initial insert OR revivication
            DELETE FROM metabib.record_attr_vector_list WHERE source = rid;
            INSERT INTO metabib.record_attr_vector_list (source, vlist) VALUES (rid, attr_vector);
        ELSE
            UPDATE metabib.record_attr_vector_list SET vlist = attr_vector WHERE source = rid;
        END IF;
    END IF;

END;

$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0875', :eg_version);

ALTER TABLE authority.record_entry ADD COLUMN heading TEXT, ADD COLUMN simple_heading TEXT;

DROP INDEX IF EXISTS authority.unique_by_heading_and_thesaurus;
DROP INDEX IF EXISTS authority.by_heading_and_thesaurus;
DROP INDEX IF EXISTS authority.by_heading;

-- Update without indexes for HOT update
UPDATE  authority.record_entry
  SET   heading = authority.normalize_heading( marc ),
        simple_heading = authority.simple_normalize_heading( marc );

CREATE INDEX by_heading_and_thesaurus ON authority.record_entry (heading) WHERE deleted IS FALSE or deleted = FALSE;
CREATE INDEX by_heading ON authority.record_entry (simple_heading) WHERE deleted IS FALSE or deleted = FALSE;

-- Add the trigger
CREATE OR REPLACE FUNCTION authority.normalize_heading_for_upsert () RETURNS TRIGGER AS $f$
BEGIN
    NEW.heading := authority.normalize_heading( NEW.marc );
    NEW.simple_heading := authority.simple_normalize_heading( NEW.marc );
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER update_headings_tgr BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.normalize_heading_for_upsert();

ALTER FUNCTION authority.normalize_heading(TEXT, BOOL) STABLE STRICT;
ALTER FUNCTION authority.normalize_heading(TEXT) STABLE STRICT;
ALTER FUNCTION authority.simple_normalize_heading(TEXT) STABLE STRICT;
ALTER FUNCTION authority.simple_heading_set(TEXT) STABLE STRICT;



SELECT evergreen.upgrade_deps_block_check('0876', :eg_version);

INSERT INTO permission.perm_list ( code, description ) VALUES
 ( 'group_application.user.staff.admin.system_admin', oils_i18n_gettext( '',
    'Allow a user to add/remove users to/from the "System Administrator" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.cat_admin', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Cataloging Administrator" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.circ_admin', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Circulation Administrator" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.data_review', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Data Review" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.volunteers', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Volunteers" group', 'ppl', 'description' ))
;


SELECT evergreen.upgrade_deps_block_check('0877', :eg_version);

-- Don't use Series search field as the browse field
UPDATE config.metabib_field SET
	browse_field = FALSE,
	browse_xpath = NULL,
	browse_sort_xpath = NULL,
	xpath = $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[not(@type="nfi")]$$
WHERE id = 1;

-- Create a new series browse config
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, search_field, authority_xpath, browse_field, browse_sort_xpath ) VALUES
    (32, 'series', 'browse', oils_i18n_gettext(32, 'Series Title (Browse)', 'cmf', 'label'), 'mods32', $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[@type="nfi"]$$, FALSE, '//@xlink:href', TRUE, $$*[local-name() != "nonSort"]$$ );

SELECT evergreen.upgrade_deps_block_check('0878', :eg_version);

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
BEGIN

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP

	-- don't store what has been normalized away
        CONTINUE WHEN ind_data.value IS NULL;

        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            CONTINUE WHEN ind_data.sort_value IS NULL;

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            SELECT INTO mbe_row * FROM metabib.browse_entry
                WHERE value = value_prepped AND sort_value = ind_data.sort_value;

            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value );

                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            -- Avoid inserting duplicate rows
            EXECUTE 'SELECT 1 FROM metabib.' || ind_data.field_class ||
                '_field_entry WHERE field = $1 AND source = $2 AND value = $3'
                INTO mbe_id USING ind_data.field, ind_data.source, ind_data.value;
                -- RAISE NOTICE 'Search for an already matching row returned %', mbe_id;
            IF mbe_id IS NULL THEN
                EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
            END IF;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('0879', :eg_version);

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point,
    tags_rstore HSTORE
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
    jrow_count  INT;
    my_using    TEXT;
    my_join     TEXT;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore

    caseless := FALSE;
    SELECT COUNT(*) INTO jrow_count FROM _vandelay_tmp_jrows;
    IF jrow_count > 0 THEN
        my_using := ' USING (record)';
        my_join := 'FULL OUTER JOIN';
    ELSE
        my_using := '';
        my_join := 'FROM';
    END IF;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    IF node.negate THEN
        IF caseless THEN
            op := 'NOT LIKE';
        ELSE
            op := '<>';
        END IF;
    ELSE
        IF caseless THEN
            op := 'LIKE';
        ELSE
            op := '=';
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := my_join || ' (SELECT *, ';
    IF node.tag IS NOT NULL THEN
        jrow := jrow  || node.quality ||
            ' AS quality FROM metabib.full_rec mfr WHERE mfr.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND mfr.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';
        jrow := jrow || vandelay._node_tag_comparisons(caseless, op, tags_rstore, tagkey);
        jrow := jrow || ')) ' || my_alias || my_using || E'\n';
    ELSE    -- svf
        jrow := jrow || 'id AS record, ' || node.quality ||
            ' AS quality FROM metabib.record_attr_flat mraf WHERE mraf.attr = ''' ||
            node.svf || ''' AND mraf.value ' || op || ' $2->''' || node.svf || ''') ' ||
            my_alias || my_using || E'\n';
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;


COMMIT;

-- re-enable the triggers we disabled before starting the transaction
ALTER TABLE authority.record_entry ENABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry ENABLE TRIGGER aaa_auth_ingest_or_delete;
ALTER TABLE authority.record_entry ENABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry ENABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry ENABLE TRIGGER map_thesaurus_to_control_set;

-- Not running changes from example.reporter-extension.sql since these are
-- not installed by default, but including a helpful note.
\qecho
\qecho **** NOTICE ****
\qecho 'There were changes in example.reporter-extension.sql.'
\qecho 'Please run that script again if you use it in your system'
\qecho 'to apply new changes.'
\qecho
\qecho
\qecho **** Certain improvements in 2.6, particularly attribute improvements,
\qecho **** require a reingest of all your bib records.  In order to allow
\qecho **** this to continue without locking your entire bibliographic data
\qecho **** set, consider generating an SQL script with the following queries,
\qecho **** then running it via psql.
\qecho ****
\qecho **** If you have a large number of bibs (100,000+), please consider this
\qecho **** as a starting point only, as you will likely wish to parallelize
\qecho **** this is some fashion.
\qecho ****
\qecho **** If you require a more responsive catalog/database while reingesting,
\qecho **** consider adding 'pg_sleep()' calls between each reingest update.
\qecho
\qecho '\\t'
\qecho '\\o /tmp/reingest_2.6_bib_recs.sql'
\qecho 'SELECT ''-- Grab current setting'';'
\qecho 'SELECT ''\\set force_reingest '' || enabled FROM config.internal_flag WHERE name = ''ingest.reingest.force_on_same_marc'';'
\qecho 'SELECT ''update config.internal_flag set enabled = true where name = ''''ingest.reingest.force_on_same_marc'''';'';'
\qecho 'SELECT ''update biblio.record_entry set id = id where id = '' || id || '';'' FROM biblio.record_entry WHERE NOT DELETED AND id > 0;'
\qecho 'SELECT ''-- Restore previous setting'';'
\qecho 'SELECT ''update config.internal_flag set enabled = :force_reingest where name = \'\'ingest.reingest.force_on_same_marc\'\';'';'
\qecho '\\o'
\qecho '\\t'
