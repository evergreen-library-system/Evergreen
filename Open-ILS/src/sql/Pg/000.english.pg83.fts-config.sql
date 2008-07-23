/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008  Equinox Software, Inc., Laurentian University
 * Mike Rylander <miker@esilibrary.com>
 * Dan Scott <dscott@laurentian.ca>
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

CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
BEGIN
	NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, NEW.value);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TEXT SEARCH DICTIONARY IF EXISTS english_nostop CASCADE;

CREATE TEXT SEARCH DICTIONARY english_nostop (TEMPLATE=pg_catalog.snowball, language='english');
COMMENT ON TEXT SEARCH DICTIONARY english_nostop IS 'English snowball stemmer with no stopwords for ASCII words only.';

CREATE TEXT SEARCH CONFIGURATION title ( COPY = pg_catalog.english );
ALTER TEXT SEARCH CONFIGURATION title ALTER MAPPING FOR word, hword, hword_part WITH pg_catalog.simple;
ALTER TEXT SEARCH CONFIGURATION title ALTER MAPPING FOR asciiword, asciihword, hword_asciipart WITH public.english_nostop;
CREATE TEXT SEARCH CONFIGURATION author ( COPY = title );
CREATE TEXT SEARCH CONFIGURATION subject ( COPY = title );
CREATE TEXT SEARCH CONFIGURATION keyword ( COPY = title );
CREATE TEXT SEARCH CONFIGURATION series ( COPY = title );
CREATE TEXT SEARCH CONFIGURATION "default" ( COPY = title );

COMMIT;
