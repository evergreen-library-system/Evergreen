CREATE OR REPLACE FUNCTION public.non_filing_normalize ( TEXT, "char" ) RETURNS TEXT AS $$
        SELECT  SUBSTRING(
                        REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                        $1,
                                        E'\W*$',
					''
				),
                                '  ',
                                ' '
                        ),
                        CASE
				WHEN $2::INT NOT BETWEEN 48 AND 57 THEN 1
				ELSE $2::TEXT::INT + 1
			END
		);
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$
	my $txt = lc(shift);
	my $sf = shift;

	$txt =~ s/\pM+//go;	# Remove diacritics

	$txt =~ s/\xE6/AE/go;	# Convert ae digraph
	$txt =~ s/\x{153}/OE/go;# Convert oe digraph
	$txt =~ s/\xFE/TH/go;	# Convert Icelandic thorn

	$txt =~ tr/\x{2070}\x{2071}\x{2072}\x{2073}\x{2074}\x{2075}\x{2076}\x{2077}\x{2078}\x{2079}\x{207A}\x{207B}/0123456789+-/;# Convert superscript numbers
	$txt =~ tr/\x{2080}\x{2081}\x{2082}\x{2083}\x{2084}\x{2085}\x{2086}\x{2087}\x{2088}\x{2089}\x{208A}\x{208B}/0123456889+-/;# Convert subscript numbers

	$txt =~ tr/\x{0251}\x{03B1}\x{03B2}\x{0262}\x{03B3}/AABGG/;	 	# Convert Latin and Greek
	$txt =~ tr/\x{2113}\xF0\!\"\(\)\-\{\}\<\>\;\:\.\?\xA1\xBF\/\\\@\*\%\=\xB1\+\xAE\xA9\x{2117}\$\xA3\x{FFE1}\xB0\^\_\~\`/LD /;	# Convert Misc
	$txt =~ tr/\'\[\]\|//d;							# Remove Misc

	if ($sf =~ /^a/o) {
		my $commapos = index($txt,',');
		if ($commapos > -1) {
			if ($commapos != length($txt) - 1) {
				my @list = split /,/, $txt;
				my $first = shift @list;
				$txt = $first . ',' . join(' ', @list);
			} else {
				$txt =~ s/,/ /go;
			}
		}
	} else {
		$txt =~ s/,/ /go;
	}

	$txt =~ s/\s+/ /go;	# Compress multiple spaces
	$txt =~ s/^\s+//o;	# Remove leading space
	$txt =~ s/\s+$//o;	# Remove trailing space

	return $txt;
$func$ LANGUAGE 'plperl' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT ) RETURNS TEXT AS $func$
	SELECT public.naco_normalize($1,'');
$func$ LANGUAGE 'sql' STRICT IMMUTABLE;

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

CREATE OR REPLACE FUNCTION public.call_number_dewey( TEXT, INT ) RETURNS TEXT AS $$
	SELECT SUBSTRING(call_number_dewey($1) FROM 1 FOR $2);
$$ LANGUAGE SQL STRICT IMMUTABLE;

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

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_at_depth ( INT,INT ) RETURNS actor.org_unit AS $$
	SELECT	a.*
	  FROM	actor.org_unit a
	  WHERE	id = ( SELECT FIRST(x.id)
	  		 FROM	actor.org_unit_ancestors($1) x
			   	JOIN actor.org_unit_type y
					ON x.ou_type = y.id AND y.depth = $2);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			UNION
	SELECT	*
	  FROM	actor.org_unit_descendants($1);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	* FROM actor.org_unit_full_path((actor.org_unit_ancestor_at_depth($1, $2)).id)
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

