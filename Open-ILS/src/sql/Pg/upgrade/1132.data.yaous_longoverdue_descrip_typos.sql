BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1132', :eg_version); -- remingtron/csharp

-- fix two typo/pasto's in setting descriptions
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'circ.copy_alerts.forgive_fines_on_long_overdue_checkin',
	'Controls whether fines are automatically forgiven when checking out an '||
	'item that has been marked as long-overdue, and the corresponding copy alert has been '||
	'suppressed.',
	'coust', 'description'
)
WHERE NAME = 'circ.copy_alerts.forgive_fines_on_long_overdue_checkin';

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'circ.longoverdue.xact_open_on_zero',
	'Leave transaction open when long-overdue balance equals zero.  ' ||
	'This leaves the long-overdue copy on the patron record when it is paid',
	'coust', 'description'
)
WHERE NAME = 'circ.longoverdue.xact_open_on_zero';

COMMIT;
