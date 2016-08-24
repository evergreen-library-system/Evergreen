BEGIN;

SELECT evergreen.upgrade_deps_block_check('0997', :eg_version);

INSERT INTO config.copy_status (id, name, holdable, opac_visible) VALUES (18,oils_i18n_gettext(18, 'Canceled Transit', 'ccs', 'name'), 't', 't');

COMMIT;
