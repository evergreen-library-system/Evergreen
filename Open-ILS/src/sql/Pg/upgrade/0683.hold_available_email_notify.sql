BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0683', :eg_version);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (5, 'check_email_notify', 1);
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (7, 'check_email_notify', 1);
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (9, 'check_email_notify', 1);
INSERT INTO action_trigger.validator (module,description) VALUES
    ('HoldNotifyCheck',
    oils_i18n_gettext(
        'HoldNotifyCheck',
        'Check Hold notification flag(s)',
        'atval',
        'description'
    ));
UPDATE action_trigger.event_definition SET validator = 'HoldNotifyCheck' WHERE id = 9;

-- NOT COVERED: Adding check_sms_notify to the proper trigger. It doesn't have a static id.

COMMIT;

--UNDO
--UPDATE action_trigger.event_definition SET validator = 'NOOP_True' WHERE id = 9;
--DELETE FROM action_trigger.event_params WHERE param = 'check_email_notify';
--DELETE FROM action_trigger.validator WHERE module = 'HoldNotifyCheck';
