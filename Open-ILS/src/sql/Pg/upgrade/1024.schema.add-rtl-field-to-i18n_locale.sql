BEGIN;

SELECT evergreen.upgrade_deps_block_check('1024', :eg_version);

-- Add new column "rtl" with default of false
ALTER TABLE config.i18n_locale ADD COLUMN rtl BOOL NOT NULL DEFAULT FALSE;

COMMIT;
