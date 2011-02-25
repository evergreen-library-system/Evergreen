BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0492'); --miker
UPDATE asset.call_number SET id = id;

COMMIT;
