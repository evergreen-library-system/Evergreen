BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

ALTER TABLE config.i18n_locale
ADD COLUMN staff_client BOOL NOT NULL DEFAULT FALSE;

UPDATE config.i18n_locale SET staff_client = TRUE WHERE code = 'en-US';

COMMIT;
