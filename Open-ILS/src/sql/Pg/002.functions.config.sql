/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008  Equinox Software, Inc.
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

/*
CREATE OR REPLACE FUNCTION oils_xml_transform ( TEXT, TEXT ) RETURNS TEXT AS $_$
	SELECT	CASE	WHEN (SELECT COUNT(*) FROM config.xml_transform WHERE name = $2 AND xslt = '---') > 0 THEN $1
			ELSE xslt_process($1, (SELECT xslt FROM config.xml_transform WHERE name = $2))
		END;
$_$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(array_to_string( array_accum( output ),' ' ),$4,'','g') FROM oils_xpath_table('id', 'marc', $1, $3, 'id='||$2)x(id INT, output TEXT);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xml_uncache (xml TEXT) RETURNS BOOL AS $func$
  delete $_SHARED{'_xslt_process'}{docs}{shift()};
  return 1;
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION oils_xml_cache (xml TEXT) RETURNS BOOL AS $func$
  use strict;
  use XML::LibXML;

  my $doc = shift;

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new();

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  # Parse and cache the doc
  eval { $_SHARED{'_xslt_process'}{docs}{$doc} = $parser->parse_string($doc) };

  return 0 if ($@);
  return 1;
$func$ LANGUAGE PLPERLU;

-- if we use these, we need to ...
drop function oils_xpath(text, text, anyarray);

CREATE OR REPLACE FUNCTION oils_xpath (xpath TEXT, xml TEXT, ns TEXT[][]) RETURNS TEXT[] AS $func$
  use strict;
  use XML::LibXML;

  my $xpath = shift;
  my $doc = shift;
  my $ns_string = shift || '';
  #elog(NOTICE,"ns_string: $ns_string");

  my %ns_list = $ns_string =~ m/\{([^{,]+),([^}]+)\}/g;
  #elog(NOTICE,"NS Prefix $_: $ns_list{$_}") for (keys %ns_list);

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = eval { $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new() };

  return undef if ($@);

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  # Look for a cached version of the doc, or parse it if none
  my $dom = eval { $_SHARED{'_xslt_process'}{docs}{$doc} || $parser->parse_string($doc) };

  return undef if ($@);

  # Cache the parsed XML doc, if already there
  $_SHARED{'_xslt_process'}{docs}{$doc} = $dom
    unless ($_SHARED{'_xslt_process'}{docs}{$doc});

  # Register the requested namespaces
  $dom->documentElement->setNamespace( $ns_list{$_} => $_ ) for ( keys %ns_list );

  # Gather and return nodes
  my @nodes = $dom->findnodes($xpath);
  #elog(NOTICE,"nodes found by $xpath: ". scalar(@nodes));

  return [ map { $_->toString } @nodes ];
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS $$SELECT oils_xpath( $1, $2, '{}'::TEXT[] );$$ LANGUAGE SQL IMMUTABLE;

*/

CREATE FUNCTION version_specific_xpath () RETURNS TEXT AS $wrapper_function$
DECLARE
    out_text TEXT;
BEGIN
    
    IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT < 8.3 THEN
        out_text := 'Creating XPath functions that work like the native XPATH function in 8.3+';
        
        EXECUTE $create_82_funcs$
                        
CREATE OR REPLACE FUNCTION oils_xpath ( xpath TEXT, xml TEXT, ns ANYARRAY ) RETURNS TEXT[] AS $func$
DECLARE
    node_text   TEXT;
    ns_regexp   TEXT;
    munged_xpath    TEXT;
BEGIN

    munged_xpath := xpath;

    IF ns IS NOT NULL AND array_upper(ns, 1) IS NOT NULL THEN
        FOR namespace IN 1 .. array_upper(ns, 1) LOOP
            munged_xpath := REGEXP_REPLACE(
                munged_xpath,
                E'(' || ns[namespace][1] || E'):(\\w+)',
                E'*[local-name() = "\\2" and namespace-uri() = "' || ns[namespace][2] || E'"]',
                'g'
            );
        END LOOP;

        munged_xpath := REGEXP_REPLACE( munged_xpath, E'\\]\\[(\\D)',E' and \\1', 'g');
    END IF;

    -- RAISE NOTICE 'munged xpath: %', munged_xpath;

    node_text := xpath_nodeset(xml, munged_xpath, 'XXX_OILS_NODESET');
    -- RAISE NOTICE 'node_text: %', node_text;

    IF munged_xpath ~ $re$/[^/[]*@[^/]+$$re$ THEN
        node_text := REGEXP_REPLACE(node_text,'<XXX_OILS_NODESET>[^"]+"', '<XXX_OILS_NODESET>', 'g');
        node_text := REGEXP_REPLACE(node_text,'"</XXX_OILS_NODESET>', '</XXX_OILS_NODESET>', 'g');
    END IF;

    node_text := REGEXP_REPLACE(node_text,'^<XXX_OILS_NODESET>', '');
    node_text := REGEXP_REPLACE(node_text,'</XXX_OILS_NODESET>$', '');

    RETURN  STRING_TO_ARRAY(node_text, '</XXX_OILS_NODESET><XXX_OILS_NODESET>');
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS $$SELECT oils_xpath( $1, $2, '{}'::TEXT[] );$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $$
    SELECT xslt_process( $1, $2 );
$$ LANGUAGE SQL IMMUTABLE;

        $create_82_funcs$;
    ELSIF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT = 8.3 THEN
        out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.3.  contrib/xml2 still required!';

        EXECUTE $create_83_funcs$
-- 8.3 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $$
    SELECT xslt_process( $1, $2 );
$$ LANGUAGE SQL IMMUTABLE;

        $create_83_funcs$;

    ELSE
        out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.4+, and plperlu-based xslt processor.  No contrib/xml2 needed!';

        EXECUTE $create_84_funcs$
-- 8.4 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $func$
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

        $create_84_funcs$;

    END IF;

    RETURN out_text;
END;
$wrapper_function$ LANGUAGE PLPGSQL;

SELECT version_specific_xpath();
DROP FUNCTION version_specific_xpath();


CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT  ARRAY_TO_STRING(
                oils_xpath(
                    $1 ||
                        CASE WHEN $1 ~ $re$/[^/[]*@[^]]+$$re$ OR $1 ~ $re$text\(\)$$re$ THEN '' ELSE '//text()' END,
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

# If we are going to convert non-ASCII characters to XML entities,
# we had better be dealing with a UTF8 string to begin with
$xml = decode_utf8($xml);

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
if ($cn =~ /^oc[nm]/) {
    $cn =~ s/^oc[nm]0*(\d+)/$1/;
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

    # If we are going to convert non-ASCII characters to XML entities,
    # we had better be dealing with a UTF8 string to begin with
    $xml = decode_utf8($xml);

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
    my $string = shift;
    my $pad = shift;
    my $len = shift;
    my $find = $len - 1;

    while ($string =~ /(?:^|\D)(\d{1,$find})(?:$|\D)/) {
        my $padded = $1;
        $padded = $pad x ($len - length($padded)) . $padded;
        $string =~ s/$1/$padded/sg;
    }

    return $string;
$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = decode_utf8(shift);
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

    my $str = decode_utf8(shift);
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

