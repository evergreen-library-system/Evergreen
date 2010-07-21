BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0347');

CREATE INDEX atev_target_def_idx ON action_trigger.event (target,event_def);

COMMIT;

