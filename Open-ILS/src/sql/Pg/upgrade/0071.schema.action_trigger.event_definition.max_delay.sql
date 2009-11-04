-- Already exists as far back as 1.6.0.0, so don't use this in version upgrades

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0071');

ALTER TABLE action_trigger.event_definition ADD COLUMN max_delay INTERVAL;

COMMIT;

