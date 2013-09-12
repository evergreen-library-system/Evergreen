BEGIN;

SELECT evergreen.upgrade_deps_block_check('0827', :eg_version);

ALTER TABLE action_trigger.event_definition ADD COLUMN repeat_delay INTERVAL;

COMMIT;

