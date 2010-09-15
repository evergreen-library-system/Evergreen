BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0401'); -- dbs

DROP INDEX authority.authority_record_unique_tcn;
ALTER TABLE authority.record_entry DROP COLUMN arn_value;
ALTER TABLE authority.record_entry DROP COLUMN arn_source;

COMMIT;
