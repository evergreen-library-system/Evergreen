-- Placeholder for backported fix
BEGIN;
SELECT evergreen.upgrade_deps_block_check('0665', :eg_version);
COMMIT;
