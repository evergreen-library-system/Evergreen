BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0506'); -- miker

ALTER FUNCTION actor.org_unit_descendants( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_descendants( INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_ancestors( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_full_path ( INT )  ROWS 2;
ALTER FUNCTION actor.org_unit_full_path ( INT, INT ) ROWS 2;
ALTER FUNCTION actor.org_unit_combined_ancestors ( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_common_ancestors ( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_ancestor_setting( TEXT, INT ) ROWS 1;
ALTER FUNCTION permission.grp_ancestors ( INT ) ROWS 1;
ALTER FUNCTION permission.usr_perms ( INT ) ROWS 10;
ALTER FUNCTION permission.usr_has_perm_at_nd ( INT, TEXT) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at_all_nd ( INT, TEXT ) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at ( INT, TEXT ) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at_all ( INT, TEXT ) ROWS 1;

CREATE OR REPLACE FUNCTION permission.grp_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE grp_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT pgt.parent, gad.distance+1
            FROM permission.grp_tree pgt JOIN grp_ancestors_distance gad ON (pgt.id = gad.id)
            WHERE pgt.parent IS NOT NULL
    )
    SELECT * FROM grp_ancestors_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION permission.grp_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE grp_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT pgt.id, gdd.distance+1
            FROM permission.grp_tree pgt JOIN grp_descendants_distance gdd ON (pgt.parent = gdd.id)
    )
    SELECT * FROM grp_descendants_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.id, oudd.distance+1
            FROM actor.org_unit ou JOIN org_unit_descendants_distance oudd ON (ou.parent_ou = oudd.id)
    )
    SELECT * FROM org_unit_descendants_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT * FROM org_unit_ancestors_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

COMMIT;

