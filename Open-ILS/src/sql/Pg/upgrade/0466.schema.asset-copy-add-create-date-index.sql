
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0466'); -- dbs

CREATE INDEX cp_create_date  ON asset.copy (create_date);

COMMIT;
