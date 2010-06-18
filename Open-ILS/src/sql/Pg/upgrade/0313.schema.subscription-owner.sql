BEGIN;

-- Org Unit Settings for configuring org unit weights and org unit max-loops for hold targeting

INSERT INTO config.upgrade_log (version) VALUES ('0313'); --miker

ALTER TABLE serial.subscription ADD COLUMN owning_lib INT NOT NULL DEFAULT 1 REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

COMMIT;

