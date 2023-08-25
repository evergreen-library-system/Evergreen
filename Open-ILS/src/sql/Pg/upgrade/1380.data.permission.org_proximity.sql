BEGIN;

SELECT evergreen.upgrade_deps_block_check('1380', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 644, 'ADMIN_PROXIMITY_ADJUSTMENT', oils_i18n_gettext(644,
    'Allow a user to administer Org Unit Proximity Adjustments', 'ppl', 'description'));

COMMIT;
