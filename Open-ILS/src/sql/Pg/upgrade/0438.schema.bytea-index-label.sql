
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0438'); -- miker

DROP INDEX asset.asset_call_number_upper_label_id_owning_lib_idx;
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (cast(upper(label) as bytea),id,owning_lib);

COMMIT;
