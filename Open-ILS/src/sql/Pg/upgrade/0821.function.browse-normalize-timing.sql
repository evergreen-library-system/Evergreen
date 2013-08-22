BEGIN;

SELECT evergreen.upgrade_deps_block_check('0821', :eg_version);

-- Placeholder script for 0821 which was backported for fixing 2.3 and 2.4 
-- only, and not master.

-- Nothing to do here.

COMMIT;
