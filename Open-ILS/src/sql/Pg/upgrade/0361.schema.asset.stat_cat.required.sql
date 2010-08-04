BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0361'); -- phasefx

ALTER TABLE asset.stat_cat ADD COLUMN required BOOL NOT NULL DEFAULT FALSE;

COMMIT;

