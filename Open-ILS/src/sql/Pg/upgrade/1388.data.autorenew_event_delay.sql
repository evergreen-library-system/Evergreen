BEGIN;

SELECT evergreen.upgrade_deps_block_check('1388', :eg_version);

UPDATE action_trigger.event_definition
SET delay = '-24:01:00'::INTERVAL
WHERE reactor = 'Circ::AutoRenew'
AND delay = '-23 hours'::INTERVAL
AND max_delay = '-1 minute'::INTERVAL;


COMMIT;
