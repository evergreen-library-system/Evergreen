BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0291'); -- dbs

DROP INDEX IF EXISTS authority.authority_record_unique_tcn;
CREATE UNIQUE INDEX authority_record_unique_tcn ON authority.record_entry (arn_source,arn_value) WHERE deleted = FALSE OR deleted IS FALSE;

DROP INDEX IF EXISTS asset.asset_call_number_label_once_per_lib;
CREATE UNIQUE INDEX asset_call_number_label_once_per_lib ON asset.call_number (record, owning_lib, label) WHERE deleted = FALSE OR deleted IS FALSE;

DROP INDEX IF EXISTS asset.copy_barcode_key;
CREATE UNIQUE INDEX copy_barcode_key ON asset.copy (barcode) WHERE deleted = FALSE OR deleted IS FALSE;

DROP INDEX IF EXISTS biblio.biblio_record_unique_tcn;
CREATE UNIQUE INDEX biblio_record_unique_tcn ON biblio.record_entry (tcn_value) WHERE deleted = FALSE OR deleted IS FALSE;

COMMIT;
