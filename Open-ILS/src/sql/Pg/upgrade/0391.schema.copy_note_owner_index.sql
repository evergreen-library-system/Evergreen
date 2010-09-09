BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0391'); -- miker
CREATE INDEX asset_copy_note_owning_copy_idx ON asset.copy_note ( owning_copy );

COMMIT;

