BEGIN;

SELECT evergreen.upgrade_deps_block_check('0814', :eg_version);

UPDATE permission.perm_list
SET description = 'Allow a user to delete a provider'
WHERE code = 'DELETE_PROVIDER';

COMMIT;
