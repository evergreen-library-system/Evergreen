BEGIN;

SELECT evergreen.upgrade_deps_block_check('0941', :eg_version);

UPDATE authority.control_set_authority_field SET sf_list = REGEXP_REPLACE( sf_list, 'e', '', 'i') WHERE tag = '100' AND control_set = 1 AND  sf_list ILIKE '%e%';

UPDATE authority.control_set_authority_field SET sf_list = REGEXP_REPLACE( sf_list, 'e', '', 'i') WHERE tag = '110' AND control_set = 1 AND  sf_list ILIKE '%e%';

COMMIT;
