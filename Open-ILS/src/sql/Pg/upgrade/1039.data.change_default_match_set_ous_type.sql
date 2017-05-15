BEGIN;

SELECT evergreen.upgrade_deps_block_check('1039', :eg_version); -- jeffdavis/gmcharlt

UPDATE config.org_unit_setting_type
SET datatype = 'link', fm_class = 'vms'
WHERE name = 'vandelay.default_match_set'
AND   datatype = 'string'
AND   fm_class IS NULL;

\echo Existing vandelay.default_match_set that do not
\echo correspond to match sets
SELECT aou.shortname, aous.value
FROM   actor.org_unit_setting aous
JOIN   actor.org_unit aou ON (aou.id = aous.org_unit)
WHERE  aous.name = 'vandelay.default_match_set'
AND    (
  value !~ '^"[0-9]+"$'
  OR
    oils_json_to_text(aous.value)::INT NOT IN (
      SELECT id FROM vandelay.match_set
    )
);

\echo And now deleting the bad values, as otherwise they
\echo will break the Library Settings Editor.
DELETE
FROM actor.org_unit_setting aous
WHERE  aous.name = 'vandelay.default_match_set'
AND    (
  value !~ '^"[0-9]+"$'
  OR
    oils_json_to_text(aous.value)::INT NOT IN (
      SELECT id FROM vandelay.match_set
    )
);

COMMIT;
