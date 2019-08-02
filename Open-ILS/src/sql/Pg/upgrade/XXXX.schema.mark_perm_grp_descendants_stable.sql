BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER FUNCTION permission.grp_descendants( INT ) STABLE;

COMMIT;
