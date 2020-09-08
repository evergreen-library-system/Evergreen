BEGIN;
  
SELECT evergreen.upgrade_deps_block_check('1222', :eg_version);

INSERT INTO action_trigger.reactor (module, description) VALUES (
    'CallHTTP', 'Push event information out to an external system via HTTP'
);

INSERT INTO action_trigger.hook (key, core_type, description, passive) VALUES (
    'bre.edit', 'bre', 'A bib record was edited', FALSE
);

COMMIT;

