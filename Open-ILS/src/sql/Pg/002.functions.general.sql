-- Rather than polluting the public schema with general Evergreen
-- functions, carve out a dedicated schema
CREATE SCHEMA evergreen;

CREATE OR REPLACE FUNCTION evergreen.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;
