BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0906', :eg_version);

ALTER FUNCTION evergreen.z3950_attr_name_is_valid (TEXT) STABLE;

COMMIT;
