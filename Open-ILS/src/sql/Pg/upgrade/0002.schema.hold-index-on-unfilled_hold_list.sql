BEGIN;
INSERT INTO config.upgrade_log (version) VALUES ('0002');
CREATE INDEX uhr_hold_idx ON action.unfulfilled_hold_list (hold);
COMMIT;
