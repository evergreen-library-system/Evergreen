BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0024');

-- This only gets inserted if there are no other id > 100 billing types
INSERT INTO config.billing_type (id, name, owner) SELECT DISTINCT 101, oils_i18n_gettext(101, 'Misc', 'cbt', 'name'), 1 FROM config.billing_type_id_seq WHERE last_value < 101;
SELECT SETVAL('config.billing_type_id_seq'::TEXT, 101);

COMMIT;
