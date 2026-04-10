BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER FUNCTION actor.org_unit_ancestors(INT) STABLE;
ALTER FUNCTION actor.org_unit_descendants(INT) STABLE;
ALTER FUNCTION actor.org_unit_descendants(INT,INT) STABLE;

COMMIT;

