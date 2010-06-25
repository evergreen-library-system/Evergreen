BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0317'); -- miker

DELETE FROM config.metabib_field_index_norm_map WHERE field = 26;
DELETE FROM config.metabib_field WHERE id = 26;

COMMIT;
