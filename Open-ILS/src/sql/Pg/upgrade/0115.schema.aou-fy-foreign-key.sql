-- Create a default row in acq.fiscal_calendar
-- Add a column in actor.org_unit to point to it

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0115'); -- Scott McKellar

INSERT INTO acq.fiscal_calendar (
	name
) VALUES (

	'Default'
);

ALTER TABLE actor.org_unit
ADD COLUMN fiscal_calendar INT NOT NULL
	REFERENCES acq.fiscal_calendar( id )
	DEFERRABLE INITIALLY DEFERRED
	DEFAULT 1;

COMMIT;
