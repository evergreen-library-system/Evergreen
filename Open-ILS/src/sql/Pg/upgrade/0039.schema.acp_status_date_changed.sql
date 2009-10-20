BEGIN;

-- Add new column status_changed_date to asset.copy, with trigger to maintain it
-- Add corresponding new column to auditor.asset_copy_history

INSERT INTO config.upgrade_log (version) VALUES ('0039'); -- mck9

ALTER TABLE asset.copy
	ADD COLUMN status_changed_time TIMESTAMPTZ;

ALTER TABLE auditor.asset_copy_history
	ADD COLUMN status_changed_time TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.status <> OLD.status THEN
		NEW.status_changed_time := now();
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_status_changed_trig
	BEFORE UPDATE ON asset.copy
	FOR EACH ROW EXECUTE PROCEDURE asset.acp_status_changed();

COMMIT;
