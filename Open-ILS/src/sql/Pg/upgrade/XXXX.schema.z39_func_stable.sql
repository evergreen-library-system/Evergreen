BEGIN;

ALTER FUNCTION evergreen.z3950_attr_name_is_valid (TEXT) STABLE;

COMMIT;
