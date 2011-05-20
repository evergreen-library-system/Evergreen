BEGIN;

SELECT evergreen.upgrade_deps_block_check('0538', :eg_version); -- senator

UPDATE action_trigger.event_definition
SET template = '[% FILTER collapse %]' || template
WHERE id = 22 AND
    SUBSTR(template, 0, 24) NOT LIKE '%FILTER collapse%';

COMMIT;
