BEGIN;

SELECT evergreen.upgrade_deps_block_check('1515', :eg_version);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.checkin.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.checkin.batch_notify',
        'Notification of a group of check ins',
        'ath',
        'description'
    ),
    FALSE
), (
    'circ.items_out.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.items_out.batch_notify',
        'Notification of a group of items out',
        'ath',
        'description'
    ),
    FALSE
), (
    'circ.renew.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.renew.batch_notify',
        'Notification of a group of renewals',
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
    'Email Check In Receipt',
    'circ.checkin.batch_notify',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.checkin_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Check In Receipt
Auto-Submitted: auto-generated

You checked in the following items:

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Barcode: [% circ.target_copy.barcode %]
    Library: [% circ.checkin_lib.name %]

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
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'checkin_lib'
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
    'Email Items Out Receipt',
    'circ.items_out.batch_notify',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.circ_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Items Out Receipt
Auto-Submitted: auto-generated

You have the following items:

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
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'circ_lib'
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
    'Email Renewal Receipt',
    'circ.renew.batch_notify',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.circ_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Renewal Receipt
Auto-Submitted: auto-generated

You renewed the following items:

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
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'circ_lib'
);

COMMIT;
