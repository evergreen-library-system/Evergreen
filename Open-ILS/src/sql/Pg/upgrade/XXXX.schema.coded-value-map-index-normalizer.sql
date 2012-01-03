-- Evergreen DB patch XXXX.schema.coded-value-map-index-normalizer.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- create the normalizer
CREATE OR REPLACE FUNCTION evergreen.coded_value_map_normalizer( input TEXT, ctype TEXT ) 
    RETURNS TEXT AS $F$
        SELECT COALESCE(value,$1) 
            FROM config.coded_value_map 
            WHERE ctype = $2 AND code = $1;
$F$ LANGUAGE SQL;

-- register the normalizer
INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
    'Coded Value Map Normalizer', 
    'Applies coded_value_map mapping of values',
    'coded_value_map_normalizer', 
    1
);

COMMIT;
