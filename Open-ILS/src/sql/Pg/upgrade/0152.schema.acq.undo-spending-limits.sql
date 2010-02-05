BEGIN;

-- Undoing some ill-considered changes...

INSERT INTO config.upgrade_log (version) VALUES ('0152'); -- Scott McKellar

ALTER TABLE actor.org_unit
	DROP COLUMN spend_warning_percent;

ALTER TABLE actor.org_unit
	DROP COLUMN spend_limit_percent;

DROP FUNCTION acq.default_spend_limit( INT );

DROP FUNCTION acq.default_warning_limit( INT );

COMMIT;

-- If there is no auditor schema, the following ALTERs
-- will fail, and that's okay.

ALTER TABLE auditor.actor_org_unit_history
	DROP COLUMN spend_warning_percent;

ALTER TABLE auditor.actor_org_unit_history
	DROP COLUMN spend_limit_percent;

