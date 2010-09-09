BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0390'); -- miker
CREATE INDEX actor_usr_usrgroup_idx ON actor.usr (usrgroup);

COMMIT;

