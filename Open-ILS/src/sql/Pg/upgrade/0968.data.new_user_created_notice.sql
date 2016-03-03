BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('0968', :eg_version); -- jstompro/gmcharlt

--create hook for actor.usr.create_date
INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.created', 'au', 'A user was created', 't');
	
--SQL to create event definition for new account creation notice
--Inactive, owned by top of org tree by default.  Modify to suit needs.

INSERT INTO action_trigger.event_definition (
    active, owner, name, hook, 
    validator, reactor, delay, delay_field,
    max_delay, template
)  VALUES (
    'f', '1', 'New User Created Welcome Notice', 'au.created',
    'NOOP_True', 'SendEmail', '10 seconds', 'create_date',
    '1 day',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Reply-To: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Subject: New Library Account Sign-up - Welcome!
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

Thank you for signing up for an account with the [% lib.name %] on [% user.create_date.substr(0, 10) %].

This email is your confirmation that your account is set up and ready as well as testing to see that we have your correct email address.

If you did not sign up for an account at the library and have received this email in error, please reply and let us know.

You can access your account online at http://catalog/eg/opac/login. From that site you can search the catalog, request materials, renew materials, leave comments, leave suggestions for titles you would like the library to purchase and update your account information.

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
[% lib.email %]

$$);
	
--insert environment values
INSERT INTO action_trigger.environment (event_def, path) VALUES
    (CURRVAL('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
    (CURRVAL('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');
	
COMMIT;
