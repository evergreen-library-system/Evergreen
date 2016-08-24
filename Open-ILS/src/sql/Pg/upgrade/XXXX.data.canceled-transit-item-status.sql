BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.copy_status (id, name) VALUES (18,oils_i18n_gettext(18, 'Canceled Transit', 'ccs', 'name'));

COMMIT;
