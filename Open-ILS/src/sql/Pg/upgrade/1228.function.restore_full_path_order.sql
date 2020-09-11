BEGIN;

SELECT evergreen.upgrade_deps_block_check('1228', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT ) RETURNS SETOF actor.org_unit AS $$
    SELECT  aou.*
      FROM  actor.org_unit AS aou
            JOIN (
                (SELECT au.id, t.depth FROM actor.org_unit_ancestors($1) AS au JOIN actor.org_unit_type t ON (au.ou_type = t.id))
                    UNION
                (SELECT au.id, t.depth FROM actor.org_unit_descendants($1) AS au JOIN actor.org_unit_type t ON (au.ou_type = t.id))
            ) AS ad ON (aou.id=ad.id)
      ORDER BY ad.depth;
$$ LANGUAGE SQL STABLE;

COMMIT;

