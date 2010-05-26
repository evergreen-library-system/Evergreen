BEGIN;

-- Insert booking schema upgrade here

CREATE TABLE actor.usr_password_reset (
  id SERIAL PRIMARY KEY,
  uuid TEXT NOT NULL, 
  usr BIGINT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED, 
  request_time TIMESTAMP NOT NULL DEFAULT NOW(), 
  has_been_reset BOOL NOT NULL DEFAULT false
);
COMMENT ON TABLE actor.usr_password_reset IS $$
/*
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 *
 * Self-serve password reset requests
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;
CREATE UNIQUE INDEX actor_usr_password_reset_uuid_idx ON actor.usr_password_reset (uuid);
CREATE INDEX actor_usr_password_reset_usr_idx ON actor.usr_password_reset (usr);
CREATE INDEX actor_usr_password_reset_request_time_idx ON actor.usr_password_reset (request_time);
CREATE INDEX actor_usr_password_reset_has_been_reset_idx ON actor.usr_password_reset (has_been_reset);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('password.reset_request','aupr','Patron has requested a self-serve password reset');
INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, template) 
    VALUES (15, 'f', 1, 'Password reset request notification', 'password.reset_request', 'NOOP_True', 'SendEmail', '00:00:01',
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
    ( 15, 'usr' );
INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 15, 'usr.home_ou' );

COMMIT;
