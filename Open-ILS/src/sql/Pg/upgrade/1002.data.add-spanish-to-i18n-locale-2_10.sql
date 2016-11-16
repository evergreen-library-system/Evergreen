BEGIN;

SELECT evergreen.upgrade_deps_block_check('1002', :eg_version);

-- This is a placeholder for the backport of schema update 1000
-- (adding es-ES to the list of locales. This script does nothing for
-- rel_2_11 and later.

COMMIT;
