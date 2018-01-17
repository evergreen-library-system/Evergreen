BEGIN;

SELECT evergreen.upgrade_deps_block_check('1086', :eg_version);

CREATE OR REPLACE FUNCTION asset.location_group_default () RETURNS TEXT AS $f$
    SELECT '!()'::TEXT; -- For now, as there's no way to cause a location group to hide all copies.
/*
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location_group')),'|') || ')'
      FROM  asset.copy_location_group
      WHERE NOT opac_visible;
*/
$f$ LANGUAGE SQL IMMUTABLE;

COMMIT;

