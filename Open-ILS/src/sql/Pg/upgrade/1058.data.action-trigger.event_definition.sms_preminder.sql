-- Evergreen DB patch XXXX.schema.action-trigger.event_definition.sms_preminder.sql
--
-- New action trigger event definition: 3 Day Courtesy Notice by SMS
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1058', :eg_version); -- mccanna/csharp/gmcharlt

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook,
        validator, reactor, delay, max_delay, delay_field, group_field, template)
    VALUES (54, FALSE, 1,
        '3 Day Courtesy Notice by SMS',
        'checkout.due',
        'CircIsOpen', 'SendSMS', '-3 days', '-2 days', 'due_date', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
[%- homelib = user.home_ou -%]
[%- sms_number = helpers.get_user_setting(user.id, 'opac.default_sms_notify') -%]
[%- sms_carrier = helpers.get_user_setting(user.id, 'opac.default_sms_carrier') -%]
From: [%- helpers.get_org_setting(homelib.id, 'org.bounced_emails') || homelib.email || params.sender_email || default_sender %]
To: [%- helpers.get_sms_gateway_email(sms_carrier,sms_number) %]
Subject: Library Materials Due Soon

You have items due soon:

[% FOR circ IN target %]
[%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
[% copy_details.title FILTER ucfirst %] by [% copy_details.author FILTER ucfirst %] due on [% date.format(helpers.format_date(circ.due_date), '%m-%d-%Y') %]

[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (54, 'circ_lib.billing_address'),
    (54, 'target_copy.call_number'),
    (54, 'usr'),
    (54, 'usr.home_ou');

COMMIT;
