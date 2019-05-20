BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

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
$$ LANGUAGE SQL STABLE ROWS 1;

COMMIT;
