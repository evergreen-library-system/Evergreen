BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0070');

ALTER TABLE action.hold_request
ADD COLUMN shelf_expire_time TIMESTAMPTZ;

COMMIT;

-- If the following ALTERs die because the table doesn't exist, don't
-- worry about it.  Some installations have it and some don't.

ALTER TABLE auditor.action_hold_request_history
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE auditor.action_hold_request_history
ADD COLUMN shelf_expire_time TIMESTAMPTZ;
