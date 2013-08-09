BEGIN;

SELECT evergreen.upgrade_deps_block_check('0804', :eg_version);

UPDATE config.coded_value_map
SET value = oils_i18n_gettext('169', 'Gwich''in', 'ccvm', 'value')
WHERE ctype = 'item_lang' AND code = 'gwi';

COMMIT;
