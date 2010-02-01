
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0145'); -- miker

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
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS $$SELECT oils_xpath( $1, $2, '{}'::TEXT[] );$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $$
    SELECT xslt_process( $1, $2 );
$$ LANGUAGE SQL;

        $create_82_funcs$;
    ELSIF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT = 8.3 THEN
        out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.3.  contrib/xml2 still required!';

        EXECUTE $create_83_funcs$
-- 8.3 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $$
    SELECT xslt_process( $1, $2 );
$$ LANGUAGE SQL;

        $create_83_funcs$;

    ELSE
        out_text := 'Creating XPath wrapper functions around the native XPATH function in 8.4+, and plperlu-based xslt processor.  No contrib/xml2 needed!';

        EXECUTE $create_84_funcs$
-- 8.4 or after
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL;

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
                        CASE WHEN $1 ~ $re$/[^/[]*@[^/]+$$re$ OR $1 ~ $re$text\(\)$$re$ THEN '' ELSE '//text()' END,
                    $2,
                    $4
                ),
                $3
            );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, $3, '{}'::TEXT[] );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, '{}'::TEXT[] );
$func$ LANGUAGE SQL;



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
$$ LANGUAGE PLPGSQL;

COMMIT;

