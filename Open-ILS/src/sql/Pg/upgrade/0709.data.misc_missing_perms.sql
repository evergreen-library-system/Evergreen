-- Evergreen DB patch 0709.data.misc_missing_perms.sql
--
-- Fixes a typo in the name of a global flag

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0709', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 
        531, 
        'ADMIN_ADDRESS_ALERT',
        oils_i18n_gettext( 
            531,
            'Allows a user to create/retrieve/update/delete address alerts',
            'ppl', 
            'description' 
        )
    ), ( 
        532, 
        'VIEW_ADDRESS_ALERT',
        oils_i18n_gettext( 
            532,
            'Allows a user to view address alerts',
            'ppl', 
            'description' 
        )
    ), ( 
        533, 
        'ADMIN_COPY_LOCATION_GROUP',
        oils_i18n_gettext( 
            533,
            'Allows a user to create/retrieve/update/delete copy location groups',
            'ppl', 
            'description' 
        )
    ), ( 
        534, 
        'ADMIN_USER_ACTIVITY_TYPE',
        oils_i18n_gettext( 
            534,
            'Allows a user to create/retrieve/update/delete user activity types',
            'ppl', 
            'description' 
        )
    );

COMMIT;
