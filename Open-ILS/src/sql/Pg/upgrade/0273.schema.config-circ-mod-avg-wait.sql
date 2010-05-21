BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0273'); -- Scott McKellar

ALTER TABLE config.circ_modifier
	ADD COLUMN avg_wait_time INTERVAL;

COMMIT;
