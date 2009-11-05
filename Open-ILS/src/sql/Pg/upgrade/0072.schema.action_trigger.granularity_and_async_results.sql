BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0072');

ALTER TABLE action_trigger.event_definition ADD COLUMN granularity TEXT;
ALTER TABLE action_trigger.event ADD COLUMN async_output BIGINT REFERENCES action_trigger.event_output (id);

COMMIT;
