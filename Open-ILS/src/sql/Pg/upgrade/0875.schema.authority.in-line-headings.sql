
ALTER TABLE authority.record_entry DISABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry DISABLE TRIGGER aaa_auth_ingest_or_delete;
ALTER TABLE authority.record_entry DISABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry DISABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry DISABLE TRIGGER map_thesaurus_to_control_set;

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0875', :eg_version);

ALTER TABLE authority.record_entry ADD COLUMN heading TEXT, ADD COLUMN simple_heading TEXT;

DROP INDEX IF EXISTS authority.unique_by_heading_and_thesaurus;
DROP INDEX IF EXISTS authority.by_heading_and_thesaurus;
DROP INDEX IF EXISTS authority.by_heading;

-- Update without indexes for HOT update
UPDATE  authority.record_entry
  SET   heading = authority.normalize_heading( marc ),
        simple_heading = authority.simple_normalize_heading( marc );

CREATE INDEX by_heading_and_thesaurus ON authority.record_entry (heading) WHERE deleted IS FALSE or deleted = FALSE;
CREATE INDEX by_heading ON authority.record_entry (simple_heading) WHERE deleted IS FALSE or deleted = FALSE;

-- Add the trigger
CREATE OR REPLACE FUNCTION authority.normalize_heading_for_upsert () RETURNS TRIGGER AS $f$
BEGIN
    NEW.heading := authority.normalize_heading( NEW.marc );
    NEW.simple_heading := authority.simple_normalize_heading( NEW.marc );
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER update_headings_tgr BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.normalize_heading_for_upsert();

ALTER FUNCTION authority.normalize_heading(TEXT, BOOL) STABLE STRICT;
ALTER FUNCTION authority.normalize_heading(TEXT) STABLE STRICT;
ALTER FUNCTION authority.simple_normalize_heading(TEXT) STABLE STRICT;
ALTER FUNCTION authority.simple_heading_set(TEXT) STABLE STRICT;

COMMIT;

ALTER TABLE authority.record_entry ENABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry ENABLE TRIGGER aaa_auth_ingest_or_delete;
ALTER TABLE authority.record_entry ENABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry ENABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry ENABLE TRIGGER map_thesaurus_to_control_set;


