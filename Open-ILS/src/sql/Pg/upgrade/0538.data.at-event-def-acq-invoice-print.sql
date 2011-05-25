BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0538'); -- senator

UPDATE action_trigger.event_definition
SET template = '[% FILTER collapse %]' || template
WHERE id = 22 AND
    SUBSTR(template, 0, 24) NOT LIKE '%FILTER collapse%';

COMMIT;
