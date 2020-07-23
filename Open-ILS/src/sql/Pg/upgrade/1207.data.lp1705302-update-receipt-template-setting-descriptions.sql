BEGIN;

SELECT evergreen.upgrade_deps_block_check('1207', :eg_version);

UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.alert_text',
            'Text to be inserted into Print Templates in place of {{includes.alert_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.alert_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.event_text',
            'Text to be inserted into Print Templates in place of {{includes.event_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.event_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.footer_text',
            'Text to be inserted into Print Templates in place of {{includes.footer_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.footer_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.header_text',
            'Text to be inserted into Print Templates in place of {{includes.header_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.header_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.notice_text',
            'Text to be inserted into Print Templates in place of {{includes.notice_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.notice_text';

COMMIT;
