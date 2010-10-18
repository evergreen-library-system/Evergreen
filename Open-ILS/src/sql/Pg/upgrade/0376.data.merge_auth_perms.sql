INSERT INTO config.upgrade_log (version) VALUES ('0376'); -- dbs

-- Permission for merging auth records may already be defined
-- so we do it outside of a transaction
INSERT INTO permission.perm_list (code, description) VALUES ('MERGE_AUTH_RECORDS', 'Allow a user to merge authority records together');
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) VALUES (4, (SELECT id FROM permission.perm_list WHERE code = 'MERGE_AUTH_RECORDS'), 1, false);
