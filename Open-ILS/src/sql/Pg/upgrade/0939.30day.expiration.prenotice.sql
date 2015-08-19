BEGIN;

SELECT evergreen.upgrade_deps_block_check('0939', :eg_version);

--create hook for actor.usr.expire_date
INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.expired', 'au', 'A user account has expired', 't');
	
--SQL to create event definition for 30 day account pre-expiration notice
--Inactive, owned by top of org tree by default.  Modify to suit needs.
--Can set reactor to 'ProcessTemplate' for testing.  Will generate emails in DB, but not actually send.

INSERT INTO action_trigger.event_definition (
    active, owner, name, hook, 
    validator, reactor, delay, delay_field,
    max_delay, repeat_delay, template
)  VALUES (
    'f', '1', '30 Day Account Expiration Courtesy Notice', 'au.expired',
    'NOOP_True', 'SendEmail', '-30 days', 'expire_date',
    '-29 days', '30 days',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Reply-To: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Subject: Courtesy Notice - Library Account Expiration in 30 days
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

Our records indicate your library account is due to expire in 30 days.  Please visit your local library at your convenience to renew your account in order to avoid a disruption in access to library service.

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
	
--insert environment values
INSERT INTO action_trigger.environment (event_def, path) VALUES
    (CURRVAL('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
    (CURRVAL('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');
	
COMMIT;
