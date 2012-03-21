-- Evergreen DB patch 0707.schema.acq-vandelay-integration.sql
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0707', :eg_version);

-- seed data --

INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 
        529, 
        'ADMIN_IMPORT_MATCH_SET',
        oils_i18n_gettext( 
            529,
            'Allows a user to create/retrieve/update/delete vandelay match sets',
            'ppl', 
            'description' 
        )
    ), ( 
        530, 
        'VIEW_IMPORT_MATCH_SET',
        oils_i18n_gettext( 
            530,
            'Allows a user to view vandelay match sets',
            'ppl', 
            'description' 
        )
    );

COMMIT;
