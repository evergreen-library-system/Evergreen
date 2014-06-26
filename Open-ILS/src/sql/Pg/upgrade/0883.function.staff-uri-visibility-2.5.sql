BEGIN;

SELECT evergreen.upgrade_deps_block_check('0883', :eg_version);

-- This is a placeholder for 0883 which will be a backported version of the
-- staff URI visibility function for rel_2_5. This script does nothing for
-- rel_2_6 and later.

COMMIT;
