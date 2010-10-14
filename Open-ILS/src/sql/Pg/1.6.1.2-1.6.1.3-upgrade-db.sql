BEGIN;

DROP INDEX asset.asset_call_number_upper_label_id_owning_lib_idx;
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (cast(upper(label) to bytea),id,owning_lib);

COMMIT;

