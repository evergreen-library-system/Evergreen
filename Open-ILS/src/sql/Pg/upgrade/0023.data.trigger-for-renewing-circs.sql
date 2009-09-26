BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0023');

-- Fix typos in descriptions
UPDATE action_trigger.hook SET description = 'A hold is successfully placed' WHERE key = 'hold_request.success';
UPDATE action_trigger.hook SET description = 'A hold is attempted but not successfully placed' WHERE key = 'hold_request.failure';

-- Add a hook for renewals
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('renewal','circ','Item renewed to user');

COMMIT;
