CREATE OR REPLACE FUNCTION public.text_concat ( TEXT, TEXT ) RETURNS TEXT AS $$
SELECT
	CASE	WHEN $1 IS NULL
			THEN $2
		WHEN $2 IS NULL
			THEN $1
		ELSE $1 || ' ' || $2
	END;
$$ LANGUAGE SQL STABLE;

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

CREATE AGGREGATE public.agg_tsvector (
	sfunc	 = public.tsvector_concat,
	basetype = tsvector,
	stype	 = tsvector
);

