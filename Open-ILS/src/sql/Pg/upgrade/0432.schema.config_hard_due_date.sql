BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0432'); -- Scott McKellar

ALTER TABLE config.rule_circ_duration
	ADD COLUMN date_ceiling TIMESTAMPTZ;

CREATE TABLE config.hard_due_date (
	id              SERIAL      PRIMARY KEY,
	duration_rule   INT         NOT NULL REFERENCES config.rule_circ_duration (id)
	                            DEFERRABLE INITIALLY DEFERRED,
	ceiling_date    TIMESTAMPTZ NOT NULL,
	active_date     TIMESTAMPTZ NOT NULL
);

COMMIT;
