BEGIN;

SELECT evergreen.upgrade_deps_block_check('1310', :eg_version);

DROP AGGREGATE IF EXISTS array_accum(anyelement) CASCADE;

COMMIT;
