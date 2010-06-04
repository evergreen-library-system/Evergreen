BEGIN;
INSERT INTO config.upgrade_log (version) VALUES ('0292'); -- dbs
CREATE UNIQUE INDEX only_one_concurrent_checkout_per_copy ON action.circulation(target_copy) WHERE checkin_time IS NULL;
COMMIT;
