-- Evergreen DB patch 0716.coded_value_map_id_seq_fix.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0716', :eg_version);

SELECT SETVAL('config.coded_value_map_id_seq'::TEXT, (SELECT max(id) FROM config.coded_value_map));

COMMIT;
