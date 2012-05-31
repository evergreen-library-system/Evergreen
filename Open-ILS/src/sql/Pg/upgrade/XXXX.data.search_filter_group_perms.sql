BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- TODO: verify IDs before merging
INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 
        537, 
        'ADMIN_SEARCH_FILTER_GROUP',
        oils_i18n_gettext( 
            537,
            'Allows staff to manage search filter groups and entries',
            'ppl', 
            'description' 
        )
    ),
    (
        538, 
        'VIEW_SEARCH_FILTER_GROUP',
        oils_i18n_gettext( 
            538,
            'Allows staff to view search filter groups and entries',
            'ppl', 
            'description' 
        )

    );

COMMIT;
