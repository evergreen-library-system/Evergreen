BEGIN;

SELECT evergreen.upgrade_deps_block_check('1259', :eg_version);

INSERT INTO action_trigger.environment (event_def,path)
SELECT id,'items' from action_trigger.event_definition WHERE name='biblio.record_entry.print.full'
AND NOT EXISTS (SELECT 1 FROM action_trigger.environment WHERE
event_def=(SELECT id FROM action_trigger.event_definition WHERE name ='biblio.record_entry.print.full' AND owner=1 LIMIT 1)
AND path='items');

INSERT INTO action_trigger.environment (event_def,path)
SELECT id,'items' from action_trigger.event_definition WHERE name='biblio.record_entry.email.full'
AND NOT EXISTS (SELECT 1 FROM action_trigger.environment WHERE
event_def=(SELECT id FROM action_trigger.event_definition WHERE name ='biblio.record_entry.email.full' AND owner=1 LIMIT 1)
AND path='items');

INSERT INTO action_trigger.environment (event_def,path)
SELECT id,'owner' from action_trigger.event_definition WHERE name='biblio.record_entry.email.full'
AND NOT EXISTS (SELECT 1 FROM action_trigger.environment WHERE
event_def=(SELECT id FROM action_trigger.event_definition WHERE name ='biblio.record_entry.email.full' AND owner=1 LIMIT 1)
AND path='owner');

COMMIT;
