BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0179'); -- dbs

INSERT INTO permission.perm_list (id, code, description)
    VALUES (363, 'ALLOW_ALT_TCN', 'Allows staff to import a record using an alternate TCN to avoid conflicts');

INSERT INTO permission.perm_list (id, code, description)
    VALUES (364, 'ADMIN_TRIGGER_EVENT_DEF', 'Allow a user to administer trigger event definitions');

COMMIT;
