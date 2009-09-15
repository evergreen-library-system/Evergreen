BEGIN;
INSERT INTO config.upgrade_log (version) VALUES ('0002.schema.hold-index-on-unfilled_hold_list.sql');
CREATE INDEX uhr_hold_idx ON action.unfulfilled_hold_list (hold);
COMMIT;
