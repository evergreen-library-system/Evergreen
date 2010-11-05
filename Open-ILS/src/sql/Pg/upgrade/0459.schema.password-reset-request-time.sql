BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0459'); -- gmc

ALTER TABLE actor.usr_password_reset ALTER COLUMN request_time TYPE TIMESTAMP WITH TIME ZONE;

COMMIT;
