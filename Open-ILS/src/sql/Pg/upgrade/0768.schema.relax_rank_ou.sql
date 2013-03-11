BEGIN;

SELECT evergreen.upgrade_deps_block_check('0768', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.rank_ou(lib INT, search_lib INT, pref_lib INT DEFAULT NULL)
RETURNS INTEGER AS $$
    SELECT COALESCE(

        -- lib matches search_lib
        (SELECT CASE WHEN $1 = $2 THEN -20000 END),

        -- lib matches pref_lib
        (SELECT CASE WHEN $1 = $3 THEN -10000 END),


        -- pref_lib is a child of search_lib and lib is a child of pref lib.  
        (SELECT distance - 5000
            FROM actor.org_unit_descendants_distance($3) 
            WHERE id = $1 AND $3 IN (
                SELECT id FROM actor.org_unit_descendants($2))),

        -- lib is a child of search_lib
        (SELECT distance FROM actor.org_unit_descendants_distance($2) WHERE id = $1),

        -- all others pay cash
        1000
    );
$$ LANGUAGE SQL STABLE;

COMMIT;

