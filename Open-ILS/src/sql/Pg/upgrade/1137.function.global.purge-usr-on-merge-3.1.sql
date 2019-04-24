BEGIN;

SELECT evergreen.upgrade_deps_block_check('1137', :eg_version);

-- This is a placeholder for 1137 which will be a backported version of the
-- actor.usr_merge function for rel_3_1. This script does nothing for
-- rel_3_2 and later.

COMMIT;
