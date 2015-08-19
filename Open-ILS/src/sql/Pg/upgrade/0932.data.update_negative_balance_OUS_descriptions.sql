BEGIN;

SELECT evergreen.upgrade_deps_block_check('0932', :eg_version);

UPDATE config.org_unit_setting_type 
    SET description = 'Default setting to prevent negative balances (refunds) on circulation related bills. Set to "true" to prohibit negative balances at all times or, when used in conjunction with an interval setting, to prohibit negative balances after a set period of time.'
    WHERE name = 'bill.prohibit_negative_balance_default';
UPDATE config.org_unit_setting_type
    SET description = 'Prevent negative balances (refunds) on bills for overdue materials. Set to "true" to prohibit negative balances at all times or, when used in conjunction with an interval setting, to prohibit negative balances after a set period of time.'
    WHERE name = 'bill.prohibit_negative_balance_on_overdues';
UPDATE config.org_unit_setting_type
    SET description = 'Prohibit negative balance on bills for lost materials. Set to "true" to prohibit negative balances at all times or, when used in conjunction with an interval setting, to prohibit negative balances after a set period of time.'
    WHERE name = 'bill.prohibit_negative_balance_on_lost';
UPDATE config.org_unit_setting_type
    SET description = 'Amount of time after which no negative balances (refunds) are allowed on circulation bills. The "Prohibit negative balance on bills" setting must also be set to "true".'
    WHERE name = 'bill.negative_balance_interval_default';
UPDATE config.org_unit_setting_type
    SET description = 'Amount of time after which no negative balances (refunds) are allowed on bills for overdue materials. The "Prohibit negative balance on bills for overdue materials" setting must also be set to "true".'
    WHERE name = 'bill.negative_balance_interval_on_overdues';
UPDATE config.org_unit_setting_type
    SET description = 'Amount of time after which no negative balances (refunds) are allowed on bills for lost/long overdue materials. The "Prohibit negative balance on bills for lost materials" setting must also be set to "true".'
    WHERE name = 'bill.negative_balance_interval_on_lost';

COMMIT;


