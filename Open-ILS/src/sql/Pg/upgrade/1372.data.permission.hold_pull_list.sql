BEGIN;

SELECT evergreen.upgrade_deps_block_check('1372', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES
 ( 643, 'VIEW_HOLD_PULL_LIST', oils_i18n_gettext(643,
    'View hold pull list', 'ppl', 'description'));

-- by default, assign VIEW_HOLD_PULL_LIST to everyone who has VIEW_HOLDS
INSERT INTO permission.grp_perm_map (perm, grp, depth, grantable)
    SELECT 643, grp, depth, grantable
    FROM permission.grp_perm_map
    WHERE perm = 9;

INSERT INTO permission.usr_perm_map (perm, usr, depth, grantable)
    SELECT 643, usr, depth, grantable
    FROM permission.usr_perm_map
    WHERE perm = 9;

COMMIT;

