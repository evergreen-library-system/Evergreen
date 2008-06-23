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

DROP AGGREGATE IF EXISTS array_accum(anyelement) CASCADE;

CREATE AGGREGATE array_accum (
	sfunc = array_append,
	basetype = anyelement,
	stype = anyarray,
	initcond = '{}'
);

CREATE OR REPLACE FUNCTION public.first_agg ( anyelement, anyelement ) RETURNS anyelement AS $$
	SELECT CASE WHEN $1 IS NULL THEN $2 ELSE $1 END;
$$ LANGUAGE SQL STABLE;

DROP AGGREGATE IF EXISTS  public.first(anyelement) CASCADE;

CREATE AGGREGATE public.first (
	sfunc	 = public.first_agg,
	basetype = anyelement,
	stype	 = anyelement
);

CREATE OR REPLACE FUNCTION public.last_agg ( anyelement, anyelement ) RETURNS anyelement AS $$
	SELECT $2;
$$ LANGUAGE SQL STABLE;

DROP AGGREGATE IF EXISTS  public.last(anyelement) CASCADE;

CREATE AGGREGATE public.last (
	sfunc	 = public.last_agg,
	basetype = anyelement,
	stype	 = anyelement
);

CREATE OR REPLACE FUNCTION public.text_concat ( TEXT, TEXT ) RETURNS TEXT AS $$
SELECT
	CASE	WHEN $1 IS NULL
			THEN $2
		WHEN $2 IS NULL
			THEN $1
		ELSE $1 || ' ' || $2
	END;
$$ LANGUAGE SQL STABLE;

DROP AGGREGATE IF EXISTS  public.agg_text(text) CASCADE;

CREATE AGGREGATE public.agg_text (
	sfunc	 = public.text_concat,
	basetype = text,
	stype	 = text
);

CREATE OR REPLACE FUNCTION public.tsvector_concat ( tsvector, tsvector ) RETURNS tsvector AS $$
SELECT
	CASE	WHEN $1 IS NULL
			THEN $2
		WHEN $2 IS NULL
			THEN $1
		ELSE $1 || ' ' || $2
	END;
$$ LANGUAGE SQL STABLE;

DROP AGGREGATE IF EXISTS  public.agg_tsvector(tsvector) CASCADE;

CREATE AGGREGATE public.agg_tsvector (
	sfunc	 = public.tsvector_concat,
	basetype = tsvector,
	stype	 = tsvector
);

COMMIT;
