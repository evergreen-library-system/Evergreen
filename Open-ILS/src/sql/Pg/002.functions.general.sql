-- Rather than polluting the public schema with general Evergreen
-- functions, carve out a dedicated schema

DROP SCHEMA IF EXISTS evergreen CASCADE;

BEGIN;

CREATE SCHEMA evergreen;

CREATE OR REPLACE FUNCTION evergreen.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

COMMIT;
