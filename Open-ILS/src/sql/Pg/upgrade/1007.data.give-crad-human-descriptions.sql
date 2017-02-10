BEGIN;

SELECT evergreen.upgrade_deps_block_check('1007', :eg_version);

UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('audience', 'Audience', 'crad', 'label')
WHERE description IS NULL
AND name = 'audience';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('bib_level', 'Bib Level', 'crad', 'label')
WHERE description IS NULL
AND name = 'bib_level';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('item_form', 'Item Form', 'crad', 'label')
WHERE description IS NULL
AND name = 'item_form';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('item_lang', 'Language', 'crad', 'label')
WHERE description IS NULL
AND name = 'item_lang';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('lit_form', 'Literary Form', 'crad', 'label')
WHERE description IS NULL
AND name = 'lit_form';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('item_type', 'Item Type', 'crad', 'label')
WHERE description IS NULL
AND name = 'item_type';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('vr_format', 'Video Format', 'crad', 'label')
WHERE description IS NULL
AND name = 'vr_format';

COMMIT;
