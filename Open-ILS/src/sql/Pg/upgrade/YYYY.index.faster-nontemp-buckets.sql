BEGIN;

CREATE INDEX IF NOT EXISTS cbreb_pub_owner_not_temp_idx ON container.biblio_record_entry_bucket (pub,owner) WHERE btype != 'temp';

COMMIT;
