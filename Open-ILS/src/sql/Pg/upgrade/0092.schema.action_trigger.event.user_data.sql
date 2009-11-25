BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0092'); -- miker

ALTER TABLE action_trigger.event ADD COLUMN user_data TEXT CHECK (user_data IS NULL OR is_json( user_data ));

COMMIT;

