
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0203'); -- miker

UPDATE biblio.record_entry SET marc = '<record xmlns="http://www.loc.gov/MARC21/slim"/>' WHERE id = -1;

COMMIT;

