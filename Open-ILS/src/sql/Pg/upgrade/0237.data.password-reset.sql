BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0237');

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'circ.password_reset_request_per_user_limit',
    oils_i18n_gettext('circ.password_reset_request_per_user_limit', 'Circulation: Maximum concurrently active self-serve password reset requests per user', 'coust', 'label'),
    oils_i18n_gettext('circ.password_reset_request_per_user_limit', 'When a user has more than this number of concurrently active self-serve password reset requests for their account, prevent the user from creating any new self-serve password reset requests until the number of active requests for the user drops back below this number.', 'coust', 'description'),
    'string'),

( 'circ.password_reset_request_time_to_live',
    oils_i18n_gettext('circ.password_reset_request_time_to_live', 'Circulation: Self-serve password reset request time-to-live', 'coust', 'label'),
    oils_i18n_gettext('circ.password_reset_request_time_to_live', 'Length of time (in seconds) a self-serve password reset request should remain active.', 'coust', 'description'),
    'string'),

( 'circ.password_reset_request_throttle',
    oils_i18n_gettext('circ.password_reset_request_throttle', 'Circulation: Maximum concurrently active self-serve password reset requests', 'coust', 'label'),
    oils_i18n_gettext('circ.password_reset_request_throttle', 'Prevent the creation of new self-serve password reset requests until the number of active requests drops back below this number.', 'coust', 'description'),
    'string')
;

INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('password.reset_request','aupr','Patron has requested a self-serve password reset');
INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, template) 
    VALUES (20, 'f', 1, 'Password reset request notification', 'password.reset_request', 'NOOP_True', 'SendEmail', '00:00:01',
$$
[%- USE date -%]
[%- user = target.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || user.home_ou.email || default_sender %]
Subject: [% user.home_ou.name %]: library account password reset request
  
You have received this message because you, or somebody else, requested a reset
of your library system password. If you did not request a reset of your library
system password, just ignore this message and your current password will
continue to work.

If you did request a reset of your library system password, please perform
the following steps to continue the process of resetting your password:

1. Open the following link in a web browser: https://[% params.hostname %]/opac/password/[% params.locale || 'en-US' %]/[% target.uuid %]
The browser displays a password reset form.

2. Enter your new password in the password reset form in the browser. You must
enter the password twice to ensure that you do not make a mistake. If the
passwords match, you will then be able to log in to your library system account
with the new password.

$$);
INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 20, 'usr' );
INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 20, 'usr.home_ou' );

COMMIT;
