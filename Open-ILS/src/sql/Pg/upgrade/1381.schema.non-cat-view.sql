BEGIN;

SELECT evergreen.upgrade_deps_block_check('1381', :eg_version);

CREATE OR REPLACE VIEW action.open_non_cataloged_circulation AS
    SELECT ncc.* 
    FROM action.non_cataloged_circulation ncc
    JOIN config.non_cataloged_type nct ON nct.id = ncc.item_type
    WHERE ncc.circ_time + nct.circ_duration > CURRENT_TIMESTAMP
;

COMMIT;


