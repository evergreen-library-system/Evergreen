BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0017');

CREATE INDEX action_circulation_target_copy_idx
ON action.circulation (target_copy);

CREATE INDEX action_aged_circulation_target_copy_idx ON
ON action.aged_circulation (target_copy);

COMMIT;
