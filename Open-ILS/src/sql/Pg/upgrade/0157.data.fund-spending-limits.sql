BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0157'); -- Scott McKellar

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
VALUES (
	'acq.fund.balance_limit.warn',
	oils_i18n_gettext('acq.fund.balance_limit.warn', 'Fund Spending Limit for Warning', 'coust', 'label'),
	oils_i18n_gettext('acq.fund.balance_limit.warn', 'When the amount remaining in the fund, including spent money and encumbrances, goes below this percentage, attempts to spend from the fund will result in a warning to the staff.', 'coust', 'descripton'),
	'integer'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
VALUES (
	'acq.fund.balance_limit.block',
	oils_i18n_gettext('acq.fnd.balance_limit.block', 'Fund Spending Limit for Block', 'coust', 'label'),
	oils_i18n_gettext('acq.fund.balance_limit.block', 'When the amount remaining in the fund, including spent money and encumbrances, goes below this percentage, attempts to spend from the fund will be blocked.', 'coust', 'description'),
	'integer'
);

COMMIT;
