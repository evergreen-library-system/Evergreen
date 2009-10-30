BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0063');

INSERT INTO action_trigger.validator (module,description) VALUES ('MinPassiveTargetAge','Check that the target is old enough to be used by this event -- requires a min_target_age interval parameter, and accepts an optional target_age_field to specify what time to use for offsetting');

COMMIT;

