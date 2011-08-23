-- Evergreen DB patch 0607.schema.oua_force_order.sql
--
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0607', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT ou.* FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad USING (id) ORDER BY ouad.distance DESC;
$$ LANGUAGE SQL ROWS 1;



COMMIT;
