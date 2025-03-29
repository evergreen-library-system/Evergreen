BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   YYY,
   'ADMIN_CALL_NUMBER_CLASS',
   oils_i18n_gettext(YYY,
     'Allow updates to call number classification names, normalizers, and fields.', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CALL_NUMBER_CLASS');

CREATE OR REPLACE FUNCTION evergreen.function_exists(function_name TEXT) RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM information_schema.routines WHERE CONCAT(routine_schema, '.', routine_name) = function_name);
$$
LANGUAGE SQL
VOLATILE;

ALTER TABLE asset.call_number_class ADD CONSTRAINT asset_call_number_class_has_valid_normalizer
    CHECK (evergreen.function_exists(normalizer));

COMMIT;
