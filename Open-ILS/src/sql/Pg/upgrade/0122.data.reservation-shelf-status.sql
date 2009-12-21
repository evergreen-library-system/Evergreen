BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0122'); -- miker

INSERT INTO config.copy_status (id,name) VALUES (15,oils_i18n_gettext(15, 'On reservation shelf', 'ccs', 'name'));

COMMIT;
