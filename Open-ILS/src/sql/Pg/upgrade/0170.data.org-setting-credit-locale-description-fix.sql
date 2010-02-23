BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0170'); -- phasefx

UPDATE config.org_unit_setting_type
    SET label = 'Global Default Locale' -- FIXME: Ironically, no I18N here nor in the seed data
    WHERE name = 'global.default_locale' AND label = 'Allow Credit Card Payments';

UPDATE config.org_unit_setting_type
    SET label = 'Allow Credit Card Payments'
    WHERE name = 'credit.payments.allow' AND label = '';

COMMIT;
