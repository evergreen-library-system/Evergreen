--Upgrade Script for 3.2.2 to 3.2.3
\set eg_version '''3.2.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.2.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1141', :eg_version);

ALTER TABLE vandelay.session_tracker
    ALTER COLUMN record_type TYPE TEXT,
    ALTER COLUMN record_type SET DEFAULT 'bib'::TEXT;

ALTER TABLE vandelay.session_tracker
    ADD CONSTRAINT vand_tracker_valid_record_type
        CHECK (record_type IN ('bib', 'authority'));


COMMIT;
