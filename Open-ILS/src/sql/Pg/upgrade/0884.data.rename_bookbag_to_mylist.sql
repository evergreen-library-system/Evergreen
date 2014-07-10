BEGIN;
-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0884', :eg_version);

UPDATE container.biblio_record_entry_bucket_type
SET label = oils_i18n_gettext(
	'bookbag',
	'Book List',
	'cbrebt',
	'label'
) WHERE code = 'bookbag';

UPDATE container.user_bucket_type
SET label = oils_i18n_gettext(
	'folks:pub_book_bags.view',
	'List Published Book Lists',
	'cubt',
	'label'
) WHERE code = 'folks:pub_book_bags.view';

UPDATE container.user_bucket_type
SET label = oils_i18n_gettext(
	'folks:pub_book_bags.add',
	'Add to Published Book Lists',
	'cubt',
	'label'
) WHERE code = 'folks:pub_book_bags.add';

UPDATE action_trigger.hook
SET description = oils_i18n_gettext(
	'container.biblio_record_entry_bucket.csv',
	'Produce a CSV file representing a book list',
	'ath',
	'description'
) WHERE key = 'container.biblio_record_entry_bucket.csv';

UPDATE action_trigger.reactor
SET description = oils_i18n_gettext(
	'ContainerCSV',
	'Facilitates producing a CSV file representing a book list by introducing an "items" variable into the TT environment, sorted as dictated according to user params',
	'atr',
	'description'
)
WHERE module = 'ContainerCSV';

UPDATE action_trigger.event_definition
SET template = REPLACE(template, 'bookbag', 'book list'),
name = 'Book List CSV'
WHERE name = 'Bookbag CSV';

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'opac.patron.temporary_list_warn',
	'Present a warning dialog to the patron when a patron adds a book to a temporary book list.',
	'coust',
	'description'
) WHERE name = 'opac.patron.temporary_list_warn';

UPDATE config.usr_setting_type
SET label = oils_i18n_gettext(
	'opac.default_list',
	'Default list to use when adding to a list',
	'cust',
	'label'
),
description = oils_i18n_gettext(
	'opac.default_list',
	'Default list to use when adding to a list',
	'cust',
	'description'
) WHERE name = 'opac.default_list';

COMMIT;
