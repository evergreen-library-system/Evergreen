-- Evergreen DB patch 0611.data.magic_macros.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0611', :eg_version);

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
(
        'circ.staff_client.receipt.header_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.header_text',
            'Receipt Template: Content of header_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.header_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(header_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.footer_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.footer_text',
            'Receipt Template: Content of footer_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.footer_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(footer_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.notice_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.notice_text',
            'Receipt Template: Content of notice_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.notice_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(notice_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.alert_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.alert_text',
            'Receipt Template: Content of alert_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.alert_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(alert_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.event_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.event_text',
            'Receipt Template: Content of event_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.event_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(event_text)%',
            'coust',
            'description'
        ),
        'string'
    );

COMMIT;
