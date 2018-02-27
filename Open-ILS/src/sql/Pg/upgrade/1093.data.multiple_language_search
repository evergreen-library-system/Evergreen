BEGIN;

SELECT evergreen.upgrade_deps_block_check('1093', :eg_version);

UPDATE config.record_attr_definition SET tag = '041', sf_list = 'abdefgm' where name = 'item_lang';

COMMIT;

