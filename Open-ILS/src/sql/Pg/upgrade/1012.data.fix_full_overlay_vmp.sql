BEGIN;

SELECT evergreen.upgrade_deps_block_check('1012', :eg_version);
UPDATE vandelay.merge_profile
SET preserve_spec = '901c',
    replace_spec = NULL
WHERE id = 2
AND   name = oils_i18n_gettext(2, 'Full Overlay', 'vmp', 'name')
AND   preserve_spec IS NULL
AND   add_spec IS NULL
AND   strip_spec IS NULL
AND   replace_spec = '901c';

COMMIT;
