BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0226');

CREATE OR REPLACE FUNCTION public.first_word ( TEXT ) RETURNS TEXT AS $$
        SELECT SUBSTRING( $1 FROM $_$^\S+$_$);
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.normalize_space( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(regexp_replace(regexp_replace($1, E'\\n', ' ', 'g'), E'(?:^\\s+)|(\\s+$)', '', 'g'), E'\\s+', ' ', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_commas( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace($1, ',', '', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_whitespace( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(normalize_space($1), E'\\s+', '', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.uppercase( TEXT ) RETURNS TEXT AS $$
    return uc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_diacritics( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFD(shift);
    $x =~ s/\pM+//go;
    return $x;

$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.entityize( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFC(shift);
    $x =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
    return $x;

$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting( setting_name TEXT, org_id INT ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    cur_org INT;
BEGIN
    cur_org := org_id;
    LOOP
        SELECT INTO setting * FROM actor.org_unit_setting WHERE org_unit = cur_org AND name = setting_name;
        IF FOUND THEN
            RETURN NEXT setting;
        END IF;
        SELECT INTO cur_org parent_ou FROM actor.org_unit WHERE id = cur_org;
        EXIT WHEN cur_org IS NULL;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

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
        select_list := ARRAY_APPEND(
            select_list,
            $sel$
            EXPLODE_ARRAY(
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
    END LOOP;

    q := $q$
SELECT * FROM (
    SELECT $q$ || ARRAY_TO_STRING( select_list, ', ' ) || $q$ FROM $q$ || relation_name || $q$ WHERE ($q$ || criteria || $q$)
)x WHERE $q$ || ARRAY_TO_STRING( where_list, ' AND ' );
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

CREATE OR REPLACE FUNCTION is_json (TEXT) RETURNS BOOL AS $func$
    use JSON::XS;
    my $json = shift();
    eval { decode_json( $json ) };
    return $@ ? 0 : 1;
$func$ LANGUAGE PLPERLU IMMUTABLE;

COMMIT;

