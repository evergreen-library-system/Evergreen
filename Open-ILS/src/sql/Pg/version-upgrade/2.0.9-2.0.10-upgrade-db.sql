-- Evergreen DB patch XXXX.data.jedi-template.sql
--
--
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0629');
INSERT INTO config.upgrade_log (version) VALUES ('2.0.10'); 

UPDATE action_trigger.event_definition
    SET template =
        REPLACE(template, 'helpers.get_li_attr', 'helpers.get_li_attr_jedi')
    WHERE id = 23;

COMMIT;
