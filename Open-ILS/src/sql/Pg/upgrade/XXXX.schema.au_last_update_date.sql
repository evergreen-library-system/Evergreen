-- Evergreen DB patch XXXX.schema.au_last_update_date.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- Add new column last_update_date to actor.usr, with trigger to maintain it
-- Add corresponding new column to auditor.actor_usr_history

ALTER TABLE actor.usr
	ADD COLUMN last_update_date TIMESTAMPTZ;

ALTER TABLE auditor.actor_usr_history
	ADD COLUMN last_update_date TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION actor.au_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_update_date := now();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER au_update_trig
	BEFORE UPDATE ON actor.usr
	FOR EACH ROW EXECUTE PROCEDURE actor.au_updated();

COMMIT;
