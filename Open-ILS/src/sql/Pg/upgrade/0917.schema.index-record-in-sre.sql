-- index serial.record_entry.record

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0917', :eg_version);

CREATE INDEX serial_record_entry_record_idx ON serial.record_entry ( record );

COMMIT;
