BEGIN;

SELECT evergreen.upgrade_deps_block_check('1504', :eg_version); -- phasefx

-- A/T seed data
INSERT into action_trigger.hook (key, core_type, description) VALUES
( 'au.erenewal', 'au', 'A patron has been renewed via Erenewal');

COMMIT;
