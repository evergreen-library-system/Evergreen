BEGIN;

SELECT evergreen.upgrade_deps_block_check('0979', :eg_version);

-- Replace connectby from the tablefunc extension with CTEs


CREATE OR REPLACE FUNCTION permission.grp_ancestors( INT ) RETURNS SETOF permission.grp_tree AS $$
    WITH RECURSIVE grp_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent, ouad.distance+1
            FROM permission.grp_tree ou JOIN grp_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent IS NOT NULL
    )
    SELECT ou.* FROM permission.grp_tree ou JOIN grp_ancestors_distance ouad USING (id) ORDER BY ouad.distance DESC;
$$ LANGUAGE SQL ROWS 1;

-- Add a utility function to find descendant groups.

CREATE OR REPLACE FUNCTION permission.grp_descendants( INT ) RETURNS SETOF permission.grp_tree AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  gr.id,
                gr.parent
          FROM  permission.grp_tree gr
          WHERE gr.id = $1
            UNION ALL
        SELECT  gr.id,
                gr.parent
          FROM  permission.grp_tree gr
                JOIN descendant_depth dd ON (dd.id = gr.parent)
    ) SELECT gr.* FROM permission.grp_tree gr JOIN descendant_depth USING (id);
$$ LANGUAGE SQL ROWS 1;

-- Add utility functions to work with permission groups as general tree-ish sets.

CREATE OR REPLACE FUNCTION permission.grp_tree_full_path ( INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  *
          FROM  permission.grp_ancestors($1)
                        UNION
        SELECT  *
          FROM  permission.grp_descendants($1);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION permission.grp_tree_combined_ancestors ( INT, INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  *
          FROM  permission.grp_ancestors($1)
                        UNION
        SELECT  *
          FROM  permission.grp_ancestors($2);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION permission.grp_tree_common_ancestors ( INT, INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  *
          FROM  permission.grp_ancestors($1)
                        INTERSECT
        SELECT  *
          FROM  permission.grp_ancestors($2);
$$ LANGUAGE SQL STABLE ROWS 1;

COMMIT;

