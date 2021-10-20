BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

DROP AGGREGATE IF EXISTS array_accum(anyelement) CASCADE;

COMMIT;
