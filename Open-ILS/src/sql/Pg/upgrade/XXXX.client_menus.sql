BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('XXXX');

UPDATE config.org_unit_setting_type SET datatype = 'string' WHERE name = 'ui.general.button_bar';

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype) VALUES ('ui.general.hotkeyset', 'Default Hotkeyset', 'Default Hotkeyset for clients (filename without the .keyset)', 'string');

UPDATE actor.org_unit_setting SET value='"circ"' WHERE name = 'ui.general.button_bar' AND value='true';

UPDATE actor.org_unit_setting SET value='"none"' WHERE name = 'ui.general.button_bar' AND value='false';

COMMIT;

