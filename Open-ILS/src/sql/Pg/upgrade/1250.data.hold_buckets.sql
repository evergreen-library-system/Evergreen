BEGIN;

SELECT evergreen.upgrade_deps_block_check('1250', :eg_version);

CREATE TABLE action.batch_hold_event (
    id          SERIAL  PRIMARY KEY,
    staff       INT     NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    bucket      INT     NOT NULL REFERENCES container.user_bucket (id) ON UPDATE CASCADE ON DELETE CASCADE,
    target      INT     NOT NULL,
    hold_type   TEXT    NOT NULL DEFAULT 'T', -- maybe different hold types in the future...
    run_date    TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    cancelled   TIMESTAMP WITH TIME ZONE
);

CREATE TABLE action.batch_hold_event_map (
    id                  SERIAL  PRIMARY KEY,
    batch_hold_event    INT     NOT NULL REFERENCES action.batch_hold_event (id) ON UPDATE CASCADE ON DELETE CASCADE,
    hold                INT     NOT NULL REFERENCES action.hold_request (id) ON UPDATE CASCADE ON DELETE CASCADE
);

INSERT INTO container.user_bucket_type (code,label) VALUES ('hold_subscription','Hold Group Container');

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'holds.subscription.randomize',
    oils_i18n_gettext(
        'holds.subscription.randomize',
        'Randomize group hold order',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'holds.subscription.randomize',
        'When placing a batch group hold, randomize the order of the patrons receiving the holds so they are not always in the same order.',
        'coust',
        'description'
    ),
    'holds',
    'bool'
);

INSERT INTO permission.perm_list (id,code,description)
  VALUES ( 628, 'MANAGE_HOLD_GROUPS', oils_i18n_gettext(628, 'Manage hold groups and hold group events', 'ppl', 'description'));

INSERT INTO action.hold_request_cancel_cause (id,label)
  VALUES ( 8, oils_i18n_gettext(8, 'Hold Group Event rollback', 'ahrcc', 'label'));

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, delay_field, group_field, cleanup_success, template)
    VALUES ('f', 1, 'Hold Group Hold Placed for Patron Email Notification', 'hold_request.success', 'NOOP_True', 'SendEmail', '30 minutes', 'request_time', 'usr', 'CreateHoldNotification',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Subcription Hold placed for you
Auto-Submitted: auto-generated

Dear [% user.family_name %], [% user.first_given_name %]
The following items have been placed on hold for you:

[% FOR hold IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(hold.current_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% hold.current_copy.call_number.label %]
    Barcode: [% hold.current_copy.barcode %]
    Library: [% hold.pickup_lib.name %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path ) VALUES
( currval('action_trigger.event_definition_id_seq'), 'usr' ),
( currval('action_trigger.event_definition_id_seq'), 'pickup_lib' ),
( currval('action_trigger.event_definition_id_seq'), 'current_copy.call_number' );


INSERT INTO action_trigger.event_definition (
    active, owner, name, hook, validator, reactor, cleanup_success,
    delay, delay_field, group_field, template
) VALUES (
    false, 1, 'Hold Group Hold Placed for Patron SMS Notification', 'hold_request.success', 'NOOP_True',
    'SendSMS', 'CreateHoldNotification', '00:30:00', 'shelf_time', 'sms_notify',
    '[%- USE date -%]
[%- user = target.0.usr -%]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, ''%a, %d %b %Y %T -0000'', gmt => 1) %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(target.0.sms_carrier,target.0.sms_notify) %]
Subject: [% target.size %] subscription hold(s) placed for you
Auto-Submitted: auto-generated

[% FOR hold IN target %][%-
  bibxml = helpers.xml_doc( hold.current_copy.call_number.record.marc );
  title = "";
  FOR part IN bibxml.findnodes(''//*[@tag="245"]/*[@code="a"]'');
    title = title _ part.textContent;
  END;
  author = bibxml.findnodes(''//*[@tag="100"]/*[@code="a"]'').textContent;
%][% hold.usr.first_given_name %]:[% title %] @ [% hold.pickup_lib.name %]
[% END %]
'
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'current_copy.call_number.record.simple_record'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib.billing_address'
);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_sms_notify', 1);


COMMIT;

