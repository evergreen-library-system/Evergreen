
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0434');

INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('template_merge','Template Merge Container');

COMMIT;

