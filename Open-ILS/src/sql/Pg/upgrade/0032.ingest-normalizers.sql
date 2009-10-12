BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0032'); -- miker

-- Some handy functions, based on existing ones, to provide optional ingest normalization

CREATE OR REPLACE FUNCTION public.left_trunc( TEXT, INT ) RETURNS TEXT AS $func$
	SELECT SUBSTRING($1,$2);
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.right_trunc( TEXT, INT ) RETURNS TEXT AS $func$
	SELECT SUBSTRING($1,1,$2);
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize_keep_comma( TEXT ) RETURNS TEXT AS $func$
	SELECT public.naco_normalize($1,'a');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.split_date_range( TEXT ) RETURNS TEXT AS $func$
	SELECT REGEXP_REPLACE( $1, E'(\\d{4})-(\\d{4})', E'\\1 \\2', 'g' );
$func$ LANGUAGE SQL STRICT IMMUTABLE;

-- And ... a table in which to register them

CREATE TABLE config.index_normalizer (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	UNIQUE NOT NULL,
	func		TEXT	NOT NULL,
	param_count	INT	NOT NULL DEFAULT 0
);

CREATE TABLE config.metabib_field_index_norm_map (
	id	SERIAL	PRIMARY KEY,
	field	INT	NOT NULL REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	norm	INT	NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	params	TEXT,
	pos	INT	NOT NULL DEFAULT 0
);

COMMIT;

