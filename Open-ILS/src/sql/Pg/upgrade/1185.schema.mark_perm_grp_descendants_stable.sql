BEGIN;

SELECT evergreen.upgrade_deps_block_check('1185', :eg_version); -- csharp / gmcharlt / jboyer

ALTER FUNCTION permission.grp_descendants( INT ) STABLE;

COMMIT;
