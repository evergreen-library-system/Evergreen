SELECT evergreen.upgrade_deps_block_check('0792', :eg_version);

UPDATE permission.perm_list SET code = 'URL_VERIFY_UPDATE_SETTINGS' WHERE id = 544 AND code = '544';

