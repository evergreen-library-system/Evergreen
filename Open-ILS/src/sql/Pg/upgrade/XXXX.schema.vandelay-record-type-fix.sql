BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE vandelay.session_tracker
    ALTER COLUMN record_type TYPE TEXT,
    ALTER COLUMN record_type SET DEFAULT 'bib'::TEXT;

ALTER TABLE vandelay.session_tracker
    ADD CONSTRAINT vand_tracker_valid_record_type
        CHECK (record_type IN ('bib', 'authority'));

COMMIT;

