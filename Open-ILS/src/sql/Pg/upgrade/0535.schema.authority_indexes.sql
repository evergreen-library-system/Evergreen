BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0535'); --dbs

CREATE INDEX authority_record_deleted_idx ON authority.record_entry(deleted) WHERE deleted IS FALSE OR deleted = false;

CREATE INDEX authority_full_rec_subfield_a_idx ON authority.full_rec (value) WHERE subfield = 'a';

COMMIT;
