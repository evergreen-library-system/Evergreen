BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0053');

INSERT INTO action_trigger.validator (module,description) VALUES ('MaxPassiveDelayAge','Check that the event is not too far past the delay_field time -- requires a max_delay_age interval parameter');

COMMIT;

