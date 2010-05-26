BEGIN;

-- action_trigger values were inserted in 0237, but we forgot about the
-- core table. Oops.

INSERT INTO config.upgrade_log (version) VALUES ('0276'); -- dbs

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

COMMIT;
