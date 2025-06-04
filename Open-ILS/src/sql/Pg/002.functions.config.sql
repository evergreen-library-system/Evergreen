/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008-2014  Equinox Software, Inc.
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


BEGIN;

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

  return $stylesheet->output_as_chars(
    $stylesheet->transform(
      $parser->parse_string($doc)
    )
  );

$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT  ARRAY_TO_STRING(
                oils_xpath(
                    $1 ||
                        CASE WHEN $1 ~ $re$/[^/[]*@[^]]+$$re$ OR $1 ~ $re$\)$$re$ THEN '' ELSE '//text()' END,
                    $2,
                    $4
                ),
                $3
            );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, $3, '{}'::TEXT[] );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, '', $3 );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, '{}'::TEXT[] );
$func$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION oils_xpath_table ( key TEXT, document_field TEXT, relation_name TEXT, xpaths TEXT, criteria TEXT ) RETURNS SETOF RECORD AS $func$
DECLARE
    xpath_list  TEXT[];
    select_list TEXT[];
    where_list  TEXT[];
    q           TEXT;
    out_record  RECORD;
    empty_test  RECORD;
BEGIN
    xpath_list := STRING_TO_ARRAY( xpaths, '|' );

    select_list := ARRAY_APPEND( select_list, key || '::INT AS key' );

    FOR i IN 1 .. ARRAY_UPPER(xpath_list,1) LOOP
        IF xpath_list[i] = 'null()' THEN
            select_list := ARRAY_APPEND( select_list, 'NULL::TEXT AS c_' || i );
        ELSE
            select_list := ARRAY_APPEND(
                select_list,
                $sel$
                unnest(
                    COALESCE(
                        NULLIF(
                            oils_xpath(
                                $sel$ ||
                                    quote_literal(
                                        CASE
                                            WHEN xpath_list[i] ~ $re$/[^/[]*@[^/]+$$re$ OR xpath_list[i] ~ $re$text\(\)$$re$ THEN xpath_list[i]
                                            ELSE xpath_list[i] || '//text()'
                                        END
                                    ) ||
                                $sel$,
                                $sel$ || document_field || $sel$
                            ),
                           '{}'::TEXT[]
                        ),
                        '{NULL}'::TEXT[]
                    )
                ) AS c_$sel$ || i
            );
            where_list := ARRAY_APPEND(
                where_list,
                'c_' || i || ' IS NOT NULL'
            );
        END IF;
    END LOOP;

    q := $q$
SELECT * FROM (
    SELECT $q$ || ARRAY_TO_STRING( select_list, ', ' ) || $q$ FROM $q$ || relation_name || $q$ WHERE ($q$ || criteria || $q$)
)x WHERE $q$ || ARRAY_TO_STRING( where_list, ' OR ' );
    -- RAISE NOTICE 'query: %', q;

    FOR out_record IN EXECUTE q LOOP
        RETURN NEXT out_record;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_tag_to_table(marc text, tag text, xpaths text[]) RETURNS SETOF record AS $function$

-- This function currently populates columns with the FIRST matching value
-- of each XPATH.  It would be reasonable to add a 'return_arrays' option
-- where each column is an array of all matching values for each path, but
-- that remains as a TODO

DECLARE
    field RECORD;
    output RECORD;
    select_list TEXT[];
    from_list TEXT[];
    q TEXT;
BEGIN
    -- setup query select
    FOR i IN 1 .. ARRAY_UPPER(xpaths,1) LOOP
        IF xpaths[i] = 'null()' THEN
            select_list := ARRAY_APPEND(select_list, 'NULL::TEXT AS c_' || i );
        ELSE
            select_list := ARRAY_APPEND(select_list, '(oils_xpath(' ||
                quote_literal(
                    CASE
                        WHEN xpaths[i] ~ $re$/[^/[]*@[^/]+$$re$ -- attribute
                            OR xpaths[i] ~ $re$text\(\)$$re$
                        THEN xpaths[i]
                        ELSE xpaths[i] || '//text()'
                    END
                ) || ', field_marc))[1] AS cl_' || i);
                -- hardcoded to first value for each path
        END IF;
    END LOOP;

    -- run query over tag set
    q := 'SELECT ' || ARRAY_TO_STRING(select_list, ',')
        || ' FROM UNNEST(oils_xpath(' || quote_literal('//*[@tag="' || tag
        || '"]') || ', ' || quote_literal(marc) || ')) AS field_marc;';
    --RAISE NOTICE '%', q;

    RETURN QUERY EXECUTE q;
END;

$function$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    query := $q$
        SELECT  regexp_replace(
                    oils_xpath_string(
                        $q$ || quote_literal($3) || $q$,
                        marc,
                        ' '
                    ),
                    $q$ || quote_literal($4) || $q$,
                    '',
                    'g')
          FROM  $q$ || $1 || $q$
          WHERE id = $q$ || $2;

    EXECUTE query INTO output;

    -- RAISE NOTICE 'query: %, output; %', query, output;

    RETURN output;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION extract_marc_field_set
        (TEXT, BIGINT, TEXT, TEXT) RETURNS SETOF TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    FOR output IN
        SELECT x.t FROM (
            SELECT id,t
                FROM  oils_xpath_table(
                    'id', 'marc', $1, $3, 'id = ' || $2)
                AS t(id int, t text))x
        LOOP
        IF $4 IS NOT NULL THEN
            SELECT INTO output (SELECT regexp_replace(output, $4, '', 'g'));
        END IF;
        RETURN NEXT output;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;


CREATE OR REPLACE FUNCTION extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
    SELECT extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL IMMUTABLE;



CREATE OR REPLACE FUNCTION oils_i18n_xlate ( keytable TEXT, keyclass TEXT, keycol TEXT, identcol TEXT, keyvalue TEXT, raw_locale TEXT ) RETURNS TEXT AS $func$
DECLARE
    locale      TEXT := REGEXP_REPLACE( REGEXP_REPLACE( raw_locale, E'[;, ].+$', '' ), E'_', '-', 'g' );
    language    TEXT := REGEXP_REPLACE( locale, E'-.+$', '' );
    result      config.i18n_core%ROWTYPE;
    fallback    TEXT;
    keyfield    TEXT := keyclass || '.' || keycol;
BEGIN

    -- Try the full locale
    SELECT  * INTO result
      FROM  config.i18n_core
      WHERE fq_field = keyfield
            AND identity_value = keyvalue
            AND translation = locale;

    -- Try just the language
    IF NOT FOUND THEN
        SELECT  * INTO result
          FROM  config.i18n_core
          WHERE fq_field = keyfield
                AND identity_value = keyvalue
                AND translation = language;
    END IF;

    -- Fall back to the string we passed in in the first place
    IF NOT FOUND THEN
	EXECUTE
            'SELECT ' ||
                keycol ||
            ' FROM ' || keytable ||
            ' WHERE ' || identcol || ' = ' || quote_literal(keyvalue)
                INTO fallback;
        RETURN fallback;
    END IF;

    RETURN result.string;
END;
$func$ LANGUAGE PLPGSQL STABLE;

-- Functions for marking translatable strings in SQL statements
-- Parameters are: primary key, string, class hint, property
CREATE OR REPLACE FUNCTION oils_i18n_gettext( INT, TEXT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_i18n_gettext( TEXT, TEXT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION is_json( TEXT ) RETURNS BOOL AS $f$
    use JSON::XS;
    my $json = shift();
    eval { JSON::XS->new->allow_nonref->decode( $json ) };
    return $@ ? 0 : 1;
$f$ LANGUAGE PLPERLU;

-- turn a JSON scalar into an SQL TEXT value
CREATE OR REPLACE FUNCTION oils_json_to_text( TEXT ) RETURNS TEXT AS $f$
    use JSON::XS;
    my $json = shift();
    my $txt;
    eval { $txt = JSON::XS->new->allow_nonref->decode( $json ) };
    return undef if ($@);
    return $txt
$f$ LANGUAGE PLPERLU;

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

    if ($_TD->{new}{source}) {
        my $plan = spi_prepare('
            SELECT source
            FROM config.bib_source
            WHERE id = $1
        ', 'INTEGER');
        my $source_name =
            spi_exec_prepared($plan, {limit => 1}, $_TD->{new}{source})->{rows}[0]{source};
        spi_freeplan($plan);
        $new_901->add_subfields("s" => $source_name) if $source_name;
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

CREATE OR REPLACE FUNCTION evergreen.force_unicode_normal_form(string TEXT, form TEXT) RETURNS TEXT AS $func$
use Unicode::Normalize 'normalize';
return normalize($_[1],$_[0]); # reverse the params
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.maintain_control_numbers() RETURNS TRIGGER AS $func$
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

CREATE OR REPLACE FUNCTION oils_text_as_bytea (TEXT) RETURNS BYTEA AS $_$
    SELECT CAST(REGEXP_REPLACE(UPPER($1), $$\\$$, $$\\\\$$, 'g') AS BYTEA);
$_$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;            # Source string
    my $pad = shift;               # string to fill. Typically '0'. This should be a single character.
    my $len = shift;               # length of resultant padded field

    $string =~ s/([0-9]+)/$pad x ($len - length($1)) . $1/eg;

    return $string;
$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # https://www.loc.gov/aba/pcc/naco/documents/SCA_PccNormalization_Final_revised.pdf
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

    # Replace curly single and double quote-like characters with straight single and double quotes
    $str =~ s/[\x{2018}\x{2019}\x{201B}\x{FF07}\x{201A}]/\x{0027}/g;
    $str =~ s/[\x{201C}\x{201D}\x{201F}\x{FF0C}\x{201E}\x{2E42}]/\x{0022}/g;

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
    # https://www.loc.gov/aba/pcc/naco/documents/SCA_PccNormalization_Final_revised.pdf
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

    # Replace curly single and double quote-like characters with straight single and double quotes
    $str =~ s/[\x{2018}\x{2019}\x{201B}\x{FF07}\x{201A}]/\x{0027}/g;
    $str =~ s/[\x{201C}\x{201D}\x{201F}\x{FF0C}\x{201E}\x{2E42}]/\x{0022}/g;

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

CREATE OR REPLACE FUNCTION public.naco_normalize_keep_comma( TEXT ) RETURNS TEXT AS $func$
        SELECT public.naco_normalize($1,'a');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT ) RETURNS TEXT AS $func$
	SELECT public.naco_normalize($1,'');
$func$ LANGUAGE 'sql' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.search_normalize_keep_comma( TEXT ) RETURNS TEXT AS $func$
        SELECT public.search_normalize($1,'a');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.search_normalize( TEXT ) RETURNS TEXT AS $func$
	SELECT public.search_normalize($1,'');
$func$ LANGUAGE 'sql' STRICT IMMUTABLE;


COMMIT;

