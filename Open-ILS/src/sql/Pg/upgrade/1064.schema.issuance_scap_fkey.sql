BEGIN;

SELECT evergreen.upgrade_deps_block_check('1064', :eg_version);

ALTER TABLE serial.issuance DROP CONSTRAINT IF EXISTS issuance_caption_and_pattern_fkey;

-- Using NOT VALID and VALIDATE CONSTRAINT limits the impact to concurrent work.
-- For details, see: https://www.postgresql.org/docs/current/static/sql-altertable.html

ALTER TABLE serial.issuance ADD CONSTRAINT issuance_caption_and_pattern_fkey
    FOREIGN KEY (caption_and_pattern)
    REFERENCES serial.caption_and_pattern (id)
    ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED
    NOT VALID;

ALTER TABLE serial.issuance VALIDATE CONSTRAINT issuance_caption_and_pattern_fkey;

COMMIT;

