BEGIN;

SELECT evergreen.upgrade_deps_block_check('1049', :eg_version); -- mmorgan/stompro/gmcharlt

\echo -----------------------------------------------------------
\echo Setting invalid age_protect and circ_as_type entries to NULL,
\echo otherwise they will break the Serial Copy Templates editor.
\echo Please review any Serial Copy Templates listed below.
\echo
UPDATE asset.copy_template act
SET age_protect = NULL
FROM actor.org_unit aou
WHERE aou.id=act.owning_lib
   AND act.age_protect NOT IN
   (
   SELECT id FROM config.rule_age_hold_protect
   )
RETURNING act.id "Template ID", act.name "Template Name",
          aou.shortname "Owning Lib",
          'Age Protection value reset to null.' "Description";

UPDATE asset.copy_template act
SET circ_as_type = NULL
FROM actor.org_unit aou
WHERE aou.id=act.owning_lib
   AND act.circ_as_type NOT IN
   (
   SELECT code FROM config.item_type_map
   )
RETURNING act.id "Template ID", act.name "Template Name",
          aou.shortname "Owning Lib",
          'Circ as Type value reset to null.' as "Description";

\echo -----------End Serial Template Fix----------------
COMMIT;
