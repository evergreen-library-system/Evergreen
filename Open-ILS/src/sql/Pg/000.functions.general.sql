-- Rather than polluting the public schema with general Evergreen
-- functions, carve out a dedicated schema

DROP SCHEMA IF EXISTS evergreen CASCADE;

BEGIN;

CREATE SCHEMA evergreen;

CREATE OR REPLACE FUNCTION evergreen.change_db_setting(setting_name TEXT, settings TEXT[]) RETURNS VOID AS $$
BEGIN
    EXECUTE 'ALTER DATABASE ' || quote_ident(current_database()) || ' SET ' || quote_ident(setting_name) || ' = ' || array_to_string(settings, ',');
END;
$$ LANGUAGE plpgsql;

SELECT evergreen.change_db_setting('search_path', ARRAY['evergreen','public','pg_catalog']);

CREATE OR REPLACE FUNCTION evergreen.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.uppercase( TEXT ) RETURNS TEXT AS $$
    return uc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.xml_escape(str TEXT) RETURNS text AS $$
    SELECT REPLACE(REPLACE(REPLACE($1,
       '&', '&amp;'),
       '<', '&lt;'),
       '>', '&gt;');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.regexp_split_to_array(TEXT, TEXT)
RETURNS TEXT[] AS $$
    return encode_array_literal([split $_[1], $_[0]]);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

-- Provide a named type for patching functions
CREATE TYPE evergreen.patch AS (patch TEXT);

CREATE OR REPLACE FUNCTION evergreen.xml_pretty_print(input XML) 
    RETURNS XML
    LANGUAGE SQL AS
$func$
SELECT xslt_process($1::text,
$$<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
    version="1.0">
   <xsl:output method="xml" omit-xml-declaration="yes" indent="yes"/>
   <xsl:strip-space elements="*"/>
   <xsl:template match="@*|node()">
     <xsl:copy>
       <xsl:apply-templates select="@*|node()"/>
     </xsl:copy>
   </xsl:template>
 </xsl:stylesheet>
$$::text)::XML
$func$;

COMMENT ON FUNCTION evergreen.xml_pretty_print(input XML) IS
'Simple pretty printer for XML, as written by Andrew Dunstan at http://goo.gl/zBHIk';

CREATE OR REPLACE FUNCTION evergreen.could_be_serial_holding_code(TEXT) RETURNS BOOL AS $$
    use JSON::XS;
    use MARC::Field;

    eval {
        my $holding_code = (new JSON::XS)->decode(shift);
        new MARC::Field('999', @$holding_code);
    };
    return 0 if $@;
    # verify that subfield labels are exactly one character long
    foreach (keys %{ { @$holding_code } }) {
        return 0 if length($_) != 1;
    }
    return 1;
$$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION evergreen.could_be_serial_holding_code(TEXT) IS
    'Return true if parameter is valid JSON representing an array that at minimum doesn''t make MARC::Field balk and only has subfield labels exactly one character long.  Otherwise false.';

CREATE OR REPLACE FUNCTION evergreen.protect_reserved_rows_from_delete() RETURNS trigger AS $protect_reserved$
BEGIN
IF OLD.id < TG_ARGV[0]::INT THEN
    RAISE EXCEPTION 'Cannot delete row with reserved ID %', OLD.id;
END IF;
RETURN OLD;
END
$protect_reserved$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
	BEGIN
	RETURN evergreen.lowercase(public.unaccent('public.unaccent', regexp_replace(arg, '[\s[:punct:]]','','g')));
	END;
$$ LANGUAGE PLPGSQL;

----- Support functions for encoding WebAuthn -----
CREATE OR REPLACE FUNCTION evergreen.gen_random_bytes_b64 (INT) RETURNS TEXT AS $f$
    SELECT encode(gen_random_bytes($1),'base64');
$f$ STRICT IMMUTABLE LANGUAGE SQL;


----- Support functions for encoding URLs -----
CREATE OR REPLACE FUNCTION evergreen.encode_base32 (TEXT) RETURNS TEXT AS $f$
  use MIME::Base32;
  my $input = shift;
  return encode_base32($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.decode_base32 (TEXT) RETURNS TEXT AS $f$
  use MIME::Base32;
  my $input = shift;
  return decode_base32($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.uri_escape (TEXT) RETURNS TEXT AS $f$
  use URI::Escape;
  my $input = shift;
  return uri_escape_utf8($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.uri_unescape (TEXT) RETURNS TEXT AS $f$
  my $input = shift;
  $input =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # inline the RE, it is 700% faster than URI::Escape::uri_unescape
  return $input;
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

COMMIT;
