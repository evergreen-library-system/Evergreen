BEGIN;

SELECT evergreen.upgrade_deps_block_check('1178', :eg_version);

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, group_field, max_delay, template) 
    VALUES (false, 1, 'Fine Limit Exceeded', 'penalty.PATRON_EXCEEDS_FINES', 'NOOP_True', 'SendEmail', '00:05:00', 'usr', '1 day', 
$$
[%- USE date -%]
[%- user = target.usr -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Fine Limit Exceeded
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],


Our records indicate your account has exceeded the fine limit allowed for the use of your library account.

Please visit the library to pay your fines and restore full access to your account.
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (currval('action_trigger.event_definition_id_seq'), 'usr'),
    (currval('action_trigger.event_definition_id_seq'), 'usr.card');

COMMIT;
