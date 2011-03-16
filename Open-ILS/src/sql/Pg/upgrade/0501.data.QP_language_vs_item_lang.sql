
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0501'); -- miker

INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('language','Language (2.0 compat version)','Lang');
UPDATE metabib.record_attr SET attrs = attrs || hstore('language',(attrs->'item_lang'));

COMMIT;
