BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0810', :eg_version);

UPDATE authority.control_set_authority_field
    SET name = REGEXP_REPLACE(name, '^See Also', 'See From')
    WHERE tag LIKE '4__' AND control_set = 1;

COMMIT;
