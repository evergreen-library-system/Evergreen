-- Evergreen DB patch 0705.data.custom-org-tree-perms.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0705', :eg_version);

INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        528, 
        'ADMIN_ORG_UNIT_CUSTOM_TREE', 
        oils_i18n_gettext( 
            528, 
            'User may update custom org unit trees', 
            'ppl', 
            'description' 
        )
    );

COMMIT;
