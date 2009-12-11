BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0114'); 

INSERT INTO permission.perm_list (id, code, description) VALUES
    (359, 'HOLD_ITEM_CHECKED_OUT.override', oils_i18n_gettext(359, 'Allows a user to place a hold on an item that they already have checked out', 'ppl', 'description'));

-- for backwards compat, give everyone the permission
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES (1, (SELECT id FROM permission.perm_list WHERE code = 'HOLD_ITEM_CHECKED_OUT.override'), 0, false);

COMMIT;
