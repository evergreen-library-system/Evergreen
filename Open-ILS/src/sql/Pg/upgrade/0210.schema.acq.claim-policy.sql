BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0210'); -- Scott McKellar

CREATE TABLE acq.claim_policy (
	id              SERIAL       PRIMARY KEY,
	org_unit        INT          NOT NULL REFERENCES actor.org_unit
	                             DEFERRABLE INITIALLY DEFERRED,
	name            TEXT         NOT NULL,
	description     TEXT         NOT NULL,
	CONSTRAINT name_once_per_org UNIQUE (org_unit, name)
);

CREATE TABLE acq.claim_policy_action (
	id              SERIAL       PRIMARY KEY,
	claim_policy    INT          NOT NULL REFERENCES acq.claim_policy
                                 ON DELETE CASCADE
	                             DEFERRABLE INITIALLY DEFERRED,
	action_interval INTERVAL     NOT NULL,
	action          INT          NOT NULL REFERENCES acq.claim_event_type
	                             DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT action_sequence UNIQUE (claim_policy, action_interval)
);

COMMIT;
