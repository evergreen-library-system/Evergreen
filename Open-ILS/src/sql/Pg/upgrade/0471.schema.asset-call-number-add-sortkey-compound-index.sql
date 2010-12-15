BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0471'); -- dbs

-- Vanquish a sequential scan in call number browsing using the simplest
-- possible approach; yes, there is duplication with asset.asset_call_number_label_once_per_lib
-- and asset.asset_call_number_label_sortkey, but let's fix the first problem
-- and worry about data loading time later if that turns out to be a real
-- problem.

CREATE INDEX asset_call_number_label_sortkey_browse ON asset.call_number(oils_text_as_bytea(label_sortkey), oils_text_as_bytea(label), id, owning_lib) WHERE deleted IS FALSE OR deleted = FALSE;

COMMIT;
