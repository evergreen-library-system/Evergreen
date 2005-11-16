CREATE OR REPLACE FUNCTION public.call_number_dewey( TEXT ) RETURNS TEXT AS $$
	my $txt = shift;
	$txt =~ s/^\s+//o;
	$txt =~ s/[\[\]\{\}\(\)`'"#<>\*\?\-\+\$\\]+//o;
	$txt =~ s/\s+$//o;
	if (/(\d{3}(?:\.\d+)?)/o) {
		return $1;
	} else {
		return (split /\s+/, $txt)[0];
	}
$$ LANGUAGE 'plperl' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.first_agg ( anyelement, anyelement ) RETURNS anyelement AS $$
	SELECT CASE WHEN $1 IS NULL THEN $2 ELSE $1 END;
$$ LANGUAGE SQL STABLE;

CREATE AGGREGATE public.first (
	sfunc	 = public.first_agg,
	basetype = anyelement,
	stype	 = anyelement
);

CREATE OR REPLACE FUNCTION public.last_agg ( anyelement, anyelement ) RETURNS anyelement AS $$
	SELECT $2;
$$ LANGUAGE SQL STABLE;

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

CREATE FUNCTION tableoid2name ( oid ) RETURNS TEXT AS $$
	BEGIN
		RETURN $1::regclass;
	END;
$$ language 'plpgsql';


CREATE OR REPLACE FUNCTION actor.org_unit_descendants ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	a.*
	  FROM	connectby('actor.org_unit','id','parent_ou','name',$1,'100','.')
	  		AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN actor.org_unit a ON a.id = t.keyid
	  ORDER BY  CASE WHEN a.parent_ou IS NULL THEN 0 ELSE 1 END, a.name;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	a.*
	  FROM	connectby('actor.org_unit','parent_ou','id','name',$1,'100','.')
	  		AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN actor.org_unit a ON a.id = t.keyid
	  ORDER BY  CASE WHEN a.parent_ou IS NULL THEN 0 ELSE 1 END, a.name;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants ( INT,INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	a.*
	  FROM	connectby('actor.org_unit','id','parent_ou','name',
	  			(SELECT	x.id
				   FROM	actor.org_unit_ancestors($1) x
				   	JOIN actor.org_unit_type y ON x.ou_type = y.id
				  WHERE	y.depth = $2)
		,'100','.')
	  		AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN actor.org_unit a ON a.id = t.keyid
	  ORDER BY  CASE WHEN a.parent_ou IS NULL THEN 0 ELSE 1 END, a.name;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			UNION
	SELECT	*
	  FROM	actor.org_unit_descendants($1);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_combined_ancestors ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			UNION
	SELECT	*
	  FROM	actor.org_unit_ancestors($2);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_common_ancestors ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			INTERSECT
	SELECT	*
	  FROM	actor.org_unit_ancestors($2);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_proximity ( INT, INT ) RETURNS INT AS $$
	SELECT COUNT(id)::INT FROM (
		SELECT id FROM actor.org_unit_combined_ancestors($1, $2)
			EXCEPT
		SELECT id FROM actor.org_unit_common_ancestors($1, $2)
	) z;
$$ LANGUAGE SQL STABLE;

CREATE AGGREGATE array_accum (
	sfunc = array_append,
	basetype = anyelement,
	stype = anyarray,
	initcond = '{}'
);
