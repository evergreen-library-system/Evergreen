BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0083');

ALTER TABLE action_trigger.event_definition ADD COLUMN usr_field TEXT;
ALTER TABLE action_trigger.event_definition ADD COLUMN opt_in_setting TEXT REFERENCES config.usr_setting_type (name) DEFERRABLE INITIALLY DEFERRED;

COMMIT;

