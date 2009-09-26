BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0024');

-- This only gets inserted if there are no other id > 100 billing types
INSERT INTO config.billing_type (name, owner) SELECT DISTINCT oils_i18n_gettext('Misc', 'Misc', 'cbt', 'name'), 1 FROM config.billing_type_id_seq WHERE last_value < 101;

COMMIT;
