BEGIN;

SELECT evergreen.upgrade_deps_block_check('1396', :eg_version);

DELETE FROM config.record_attr_definition
WHERE name = 'on_reserve';

COMMIT;
