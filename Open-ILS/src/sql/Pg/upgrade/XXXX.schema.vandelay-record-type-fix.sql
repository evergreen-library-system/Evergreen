BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


ALTER TABLE vandelay.session_tracker
    ALTER COLUMN record_type TYPE TEXT;

ALTER TABLE vandelay.session_tracker
    ADD CONSTRAINT vand_tracker_valid_record_type
        CHECK (record_type IN ('bib', 'authority'));

END;
$$ LANGUAGE plpgsql;

COMMIT;