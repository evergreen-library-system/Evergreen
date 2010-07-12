BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0333'); --gmc

-- must create this rule explicitly; it is not inherited from asset.copy
CREATE RULE protect_serial_unit_delete AS ON DELETE TO serial.unit DO INSTEAD UPDATE serial.unit SET deleted = TRUE WHERE OLD.id = serial.unit.id;

COMMIT;
