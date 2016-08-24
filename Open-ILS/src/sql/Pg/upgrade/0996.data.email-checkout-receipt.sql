BEGIN;

SELECT evergreen.upgrade_deps_block_check('0996', :eg_version);

INSERT INTO config.usr_setting_type (
    name,
    opac_visible,
    label,
    description,
    datatype
) VALUES (
    'circ.send_email_checkout_receipts',
    TRUE,
    oils_i18n_gettext('circ.send_email_checkout_receipts', 'Email checkout receipts by default?', 'cust', 'label'),
    oils_i18n_gettext('circ.send_email_checkout_receipts', 'Email checkout receipts by default?', 'cust', 'description'),
    'bool'
);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.checkout.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.checkout.batch_notify',
        'Notification of a group of circs',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.checkout.batch_notify.session',
    'circ',
    oils_i18n_gettext(
        'circ.checkout.batch_notify.session',
        'Notification of a group of circs at the end of a checkout session',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    usr_field,
    opt_in_setting,
    group_field,
    template
) VALUES (
    TRUE,
    1,
    'Email Checkout Receipt',
    'circ.checkout.batch_notify.session',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.circ_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Checkout Receipt
Auto-Submitted: auto-generated

You checked out the following items:

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Barcode: [% circ.target_copy.barcode %]
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Library: [% circ.circ_lib.name %]

[% END %]
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.call_number'
), (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.location'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'circ_lib'
);

COMMIT;

