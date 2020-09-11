BEGIN;

SELECT evergreen.upgrade_deps_block_check('1229', :eg_version);


INSERT into action_trigger.hook (key, core_type, description) VALUES (
    'au.email.test', 'au', 'A test email has been requested for this user'
),
(
    'au.sms_text.test', 'au', 'A test SMS has been requested for this user'
);

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send Test Email', 'au.email.test', 'NOOP_True', 'SendEmail', '00:01:00', 
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- user.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Reply-To: [%- lib.email || params.sender_email || default_sender %]
Subject: Email Test Notification
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

This is a test of the email associated with your account at [%- lib.name -%]. If you are receiving this message, your email information is correct.

Sincerely,
[% lib.name %]

Contact your library for more information:

[% lib.name %]
[%- SET addr = lib.mailing_address -%]
[%- IF !addr -%] [%- SET addr = lib.billing_address -%] [%- END %]
[% addr.street1 %] [% addr.street2 %]
[% addr.city %], [% addr.state %]
[% addr.post_code %]
[% lib.phone %]
$$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send Test SMS', 'au.sms_text.test', 'NOOP_True', 'SendSMS', '00:01:00', 
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = user.home_ou -%]
[%- sms_number = helpers.get_user_setting(target.id, 'opac.default_sms_notify') -%]
[%- sms_carrier = helpers.get_user_setting(target.id, 'opac.default_sms_carrier') -%]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
To: [%- helpers.get_sms_gateway_email(sms_carrier,sms_number) %]
Subject: Test Text Message

This is a test confirming your mobile number for [% lib.name %] is correct.

Sincerely,
[% lib.name %]

Contact your library for more information:

[% lib.name %]
[%- SET addr = lib.mailing_address -%]
[%- IF !addr -%] [%- SET addr = lib.billing_address -%] [%- END %]
[% addr.street1 %] [% addr.street2 %]
[% addr.city %], [% addr.state %]
[% addr.post_code %]
[% lib.phone %]
$$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');


COMMIT;
