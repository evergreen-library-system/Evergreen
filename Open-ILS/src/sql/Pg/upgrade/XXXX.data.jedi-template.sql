-- Evergreen DB patch XXXX.data.jedi-template.sql
--
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE action_trigger.event_definition
    SET template =
        REPLACE(template, 'helpers.get_li_attr', 'helpers.get_li_attr_jedi')
    WHERE id = 23;

COMMIT;
