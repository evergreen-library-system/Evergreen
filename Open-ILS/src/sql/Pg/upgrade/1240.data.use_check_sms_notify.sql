BEGIN;

SELECT evergreen.upgrade_deps_block_check('1240', :eg_version);

INSERT INTO action_trigger.event_params (event_def, param, value)
SELECT id, 'check_sms_notify', 1
FROM action_trigger.event_definition
WHERE reactor = 'SendSMS'
AND validator IN ('HoldIsAvailable', 'HoldIsCancelled', 'HoldNotifyCheck')
AND NOT EXISTS (
    SELECT * FROM action_trigger.event_params
    WHERE param = 'check_sms_notify'
);

COMMIT;
