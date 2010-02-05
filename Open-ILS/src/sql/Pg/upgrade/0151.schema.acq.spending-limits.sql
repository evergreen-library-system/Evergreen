BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0151'); -- Scott McKellar

ALTER TABLE actor.org_unit
	ADD COLUMN spend_warning_percent INT
	CONSTRAINT spend_warning_percent_limit 
		CHECK( spend_warning_percent <= 100 );

ALTER TABLE actor.org_unit
	ADD COLUMN spend_limit_percent INT
	CONSTRAINT spend_limit_percent_limit 
		CHECK( spend_limit_percent <= 100 );

CREATE OR REPLACE FUNCTION acq.default_spend_limit( org_unit_id IN INT )
RETURNS INTEGER AS $$
DECLARE
	org     INT;
	key_id  INT;
	percent INT;
	parent  INT;
BEGIN
	org := org_unit_id;
	WHILE percent IS NULL LOOP
		SELECT
			id,
			spend_limit_percent,
			parent_ou
		INTO
			key_id,
			percent,
			parent
		FROM
			actor.org_unit
		WHERE
			id = org;
		--
		IF key_id IS NULL THEN
			RAISE EXCEPTION 'Org_unit id % is not valid', org_unit_id; 
		END IF;
		--
		IF parent IS NULL THEN
			EXIT;
		ELSE
			org := parent;
		END IF;
	END LOOP;
	--
	IF percent IS NULL THEN
		RETURN 0;              -- Last-ditch default
	ELSE
		RETURN percent;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.default_warning_limit( org_unit_id IN INT )
RETURNS INTEGER AS $$
DECLARE
	org     INT;
	key_id  INT;
	percent INT;
	parent  INT;
BEGIN
	org := org_unit_id;
	WHILE percent IS NULL LOOP
		SELECT
			id,
			spend_warning_percent,
			parent_ou
		INTO
			key_id,
			percent,
			parent
		FROM
			actor.org_unit
		WHERE
			id = org;
		--
		IF key_id IS NULL THEN
			RAISE EXCEPTION 'Org_unit id % is not valid', org_unit_id; 
		END IF;
		--
		IF parent IS NULL THEN
			EXIT;
		ELSE
			org := parent;
		END IF;
	END LOOP;
	--
	IF percent IS NULL THEN
		RETURN 10;             -- Last-ditch default
	ELSE
		RETURN percent;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

COMMIT;

-- If there is no auditor schema, the following ALTERs
-- will fail, and that's okay.  The first one will fail
-- if the fiscal_calendar column is already present.

ALTER TABLE auditor.actor_org_unit_history
	ADD COLUMN fiscal_calendar INT;

ALTER TABLE auditor.actor_org_unit_history
	ADD COLUMN spend_warning_percent INT;

ALTER TABLE auditor.actor_org_unit_history
	ADD COLUMN spend_limit_percent INT;

