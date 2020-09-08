BEGIN;

SELECT evergreen.upgrade_deps_block_check('1223', :eg_version);

-- First, normalize the au.create[d] and au.update[d] hooks.  The code and seed data differ.

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.created', 'au', 'A user was created', 't') ON CONFLICT DO NOTHING;
INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.updated', 'au', 'A user was updated', 't') ON CONFLICT DO NOTHING;


UPDATE action_trigger.event_definition SET hook = 'au.created' WHERE hook = 'au.create';
UPDATE action_trigger.event_definition SET hook = 'au.updated' WHERE hook = 'au.update';

DELETE FROM action_trigger.hook WHERE key = 'au.create';
DELETE FROM action_trigger.hook WHERE key = 'au.update';

-- Now the entirely new ones...
INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.renewed', 'au', 'A user was renewed by having their expire date changed', 't');

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.barcode_changed', 'au', 'A card was updated or created for an existing user', 't');

COMMIT;
