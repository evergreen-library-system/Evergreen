-- index serial.record_entry.record

BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX serial_record_entry_record_idx ON serial.record_entry ( record );

COMMIT;
