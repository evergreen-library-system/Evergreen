BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0040'); -- miker

ALTER TABLE action.hold_request ADD COLUMN cut_in_line BOOL;

COMMIT;

ALTER TABLE auditor.action_hold_request_history ADD COLUMN cut_in_line BOOL;

