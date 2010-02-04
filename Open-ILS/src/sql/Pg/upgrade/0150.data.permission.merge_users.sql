BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0150'); -- dbs

INSERT INTO permission.perm_list (id, code, description)
    VALUES (362, 'MERGE_USERS', 'Allows user records to be merged');

COMMIT;
