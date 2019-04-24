BEGIN;

SELECT evergreen.upgrade_deps_block_check('1129', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.cancel_reason', 'gui', 'object',
    oils_i18n_gettext (
        'eg.grid.admin.acq.cancel_reason',
        'Grid Config: admin.acq.cancel_reason',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_event_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_event_type',
        'Grid Config: admin.acq.claim_event_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_policy', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_policy',
        'Grid Config: admin.acq.claim_policy',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_policy_action', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_policy_action',
        'Grid Config: admin.acq.claim_policy_action',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.claim_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.claim_type',
        'Grid Config: admin.acq.claim_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.currency_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.currency_type',
        'Grid Config: admin.acq.currency_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.edi_account', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.edi_account',
        'Grid Config: admin.acq.edi_account',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.edi_message', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.edi_message',
        'Grid Config: admin.acq.edi_message',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.exchange_rate', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.exchange_rate',
        'Grid Config: admin.acq.exchange_rate',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.fund_tag', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.fund_tag',
        'Grid Config: admin.acq.fund_tag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.invoice_item_type', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.invoice_item_type',
        'Grid Config: admin.acq.invoice_item_type',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.invoice_payment_method', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.invoice_payment_method',
        'Grid Config: admin.acq.invoice_payment_method',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.lineitem_alert_text', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.lineitem_alert_text',
        'Grid Config: admin.acq.lineitem_alert_text',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.lineitem_marc_attr_definition', 'gui', 'object',
    oils_i18n_gettext (
    'eg.grid.admin.acq.lineitem_marc_attr_definition',
        'Grid Config: admin.acq.lineitem_marc_attr_definition',
        'cwst', 'label'
    )
);

COMMIT;
