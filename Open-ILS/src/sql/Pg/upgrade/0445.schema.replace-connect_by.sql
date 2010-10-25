BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0445'); -- miker

CREATE OR REPLACE FUNCTION actor.org_unit_descendants( INT, INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id)
          WHERE ad.depth = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ) SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ) SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou
          FROM  actor.org_unit ou
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou
          FROM  actor.org_unit ou
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ) SELECT ou.* FROM actor.org_unit ou JOIN anscestor_depth USING (id);
$$ LANGUAGE SQL;

COMMIT;

