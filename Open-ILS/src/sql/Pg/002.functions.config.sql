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



CREATE TYPE biblio_field_vtype AS ( record BIGINT, field INT, content TEXT );
CREATE OR REPLACE FUNCTION biblio_field_table ( record BIGINT, field_list INT[] ) RETURNS SETOF biblio_field_vtype AS $_$
DECLARE
	i INT;
	rec biblio_field_vtype%ROWTYPE;
BEGIN
	FOR i IN ARRAY_LOWER(field_list,1) .. ARRAY_UPPER(field_list,1) LOOP
		FOR rec IN      SELECT	DISTINCT r, field_list[i], BTRIM(REGEXP_REPLACE(REGEXP_REPLACE(f, E'\n', ' ', 'g'), '[ ]+', ' ', 'g'))
				  FROM	xpath_table_ns(
    						'id',
	    					$$oils_xml_transform(marc,'$$ || (SELECT format FROM config.metabib_field WHERE id = field_list[i]) || $$')$$,
		    				'biblio.record_entry',
			    			(SELECT xpath FROM config.metabib_field WHERE id = field_list[i]),
				    		'id = ' || record,
					    	(SELECT x.prefix FROM config.xml_transform x JOIN config.metabib_field m ON (m.format = x.name) WHERE m.id = field_list[i]),
						    (SELECT x.namespace_uri FROM config.xml_transform x JOIN config.metabib_field m ON (m.format = x.name) WHERE m.id = field_list[i])
    					) AS t( r bigint, f text)
				  WHERE f IS NOT NULL LOOP
			RETURN NEXT rec;
		END LOOP;
	END LOOP;
END;
$_$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION biblio_field_table ( record BIGINT, field INT ) RETURNS SETOF biblio_field_vtype AS $_$
	SELECT * FROM biblio_field_table( $1, ARRAY[$2] )
$_$ LANGUAGE SQL;

*/

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(array_to_string( array_accum( output ),' ' ),$4,'','g') FROM xpath_table('id', 'marc', $1, $3, 'id='||$2)x(id INT, output TEXT);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL;

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
$func$ LANGUAGE PLPGSQL;

-- Functions for marking translatable strings in SQL statements
-- Parameters are: primary key, string, class hint, property
CREATE OR REPLACE FUNCTION oils_i18n_gettext( INT, TEXT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_i18n_gettext( TEXT, TEXT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.first_word ( TEXT ) RETURNS TEXT AS $$
        SELECT SUBSTRING( $1 FROM $_$^\S+$_$);
$$ LANGUAGE SQL;

COMMIT;

