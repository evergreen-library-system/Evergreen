BEGIN;

SELECT evergreen.upgrade_deps_block_check('1184', :eg_version);

INSERT INTO permission.perm_list(id, code, description)
    VALUES (618, 'CREATE_PRECAT', 'Allows user to create a pre-catalogued copy');

-- Add this new permission to any group with Staff login perm.
-- Manually remove if needed
INSERT INTO permission.grp_perm_map(perm, grp, depth) SELECT 618, map.grp, 0 FROM permission.grp_perm_map AS map WHERE map.perm = 2;

COMMIT;
