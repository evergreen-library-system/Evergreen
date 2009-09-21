BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0009.data.action-trigger-hold-cancel-hook.sql');

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.expire_no_target',
    'ahr',
    'A hold is cancelled because no copies were found'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.expire_holds_shelf',
    'ahr',
    'A hold is cancelled becuase it was on the holds shelf too long'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.staff',
    'ahr',
    'A hold is cancelled becuase it was cancelled by staff'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.patron',
    'ahr',
    'A hold is cancelled by the patron'
);


COMMIT;


