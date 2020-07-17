BEGIN;

SELECT evergreen.upgrade_deps_block_check('1206', :eg_version);

CREATE OR REPLACE FUNCTION
    action.hold_request_regen_copy_maps(
        hold_id INTEGER, copy_ids INTEGER[]) RETURNS VOID AS $$
    DELETE FROM action.hold_copy_map WHERE hold = $1;
    INSERT INTO action.hold_copy_map (hold, target_copy) SELECT DISTINCT $1, UNNEST($2);
$$ LANGUAGE SQL;

COMMIT;
