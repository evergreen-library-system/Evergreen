BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0425'); -- Scott McKellar

ALTER TABLE permission.grp_tree
	ADD COLUMN hold_priority INT NOT NULL DEFAULT 0;

COMMIT;
