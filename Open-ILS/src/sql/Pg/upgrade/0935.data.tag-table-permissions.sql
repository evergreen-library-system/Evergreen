BEGIN;

SELECT evergreen.upgrade_deps_block_check('0935', :eg_version);

INSERT INTO permission.perm_list ( code, description ) VALUES
 ( 'ADMIN_TAG_TABLE', oils_i18n_gettext( '',
    'Allow administration of MARC tag tables', 'ppl', 'description'
 ));

COMMIT;
