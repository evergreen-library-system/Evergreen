BEGIN;

SELECT evergreen.upgrade_deps_block_check('0675', :eg_version);

-- set expected row count to low value to avoid problem
-- where use of this function by the circ tagging feature
-- results in full scans of asset.call_number
CREATE OR REPLACE FUNCTION action.usr_visible_circ_copies( INTEGER ) RETURNS SETOF BIGINT AS $$
    SELECT DISTINCT(target_copy) FROM action.usr_visible_circs($1)
$$ LANGUAGE SQL ROWS 10;

COMMIT;
