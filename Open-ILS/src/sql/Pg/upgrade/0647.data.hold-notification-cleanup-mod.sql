-- Evergreen DB patch XXXX.data.hold-notification-cleanup-mod.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0647', :eg_version);

INSERT INTO action_trigger.cleanup ( module, description ) VALUES (
    'CreateHoldNotification',
    oils_i18n_gettext(
        'CreateHoldNotification',
        'Creates a hold_notification record for each notified hold',
        'atclean',
        'description'
    )
);

UPDATE action_trigger.event_definition 
    SET 
        cleanup_success = 'CreateHoldNotification' 
    WHERE 
        id = 5 -- stock hold-ready email event_def
        AND cleanup_success IS NULL; -- don't clobber any existing cleanup mod

COMMIT;
