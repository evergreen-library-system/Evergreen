BEGIN;

SELECT evergreen.upgrade_deps_block_check('0861', :eg_version);

CREATE INDEX authority_record_entry_create_date_idx ON authority.record_entry ( create_date );
CREATE INDEX authority_record_entry_edit_date_idx ON authority.record_entry ( edit_date );

COMMIT;
