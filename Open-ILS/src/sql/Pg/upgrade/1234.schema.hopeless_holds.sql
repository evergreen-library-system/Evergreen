BEGIN;

SELECT evergreen.upgrade_deps_block_check('1234', :eg_version);

ALTER TABLE config.copy_status ADD COLUMN hopeless_prone BOOL NOT NULL DEFAULT FALSE; -- 002.schema.config.sql
ALTER TABLE action.hold_request ADD COLUMN hopeless_date TIMESTAMP WITH TIME ZONE; -- 090.schema.action.sql

COMMIT;
