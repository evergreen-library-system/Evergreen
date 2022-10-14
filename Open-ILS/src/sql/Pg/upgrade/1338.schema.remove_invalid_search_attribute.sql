-- remove invalid search attribute Item Type from LC Z39.50 target

BEGIN;

SELECT evergreen.upgrade_deps_block_check('1338', :eg_version);

DELETE FROM config.z3950_attr WHERE source = 'loc' AND code = 1001;

COMMIT;
