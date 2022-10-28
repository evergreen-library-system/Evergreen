BEGIN;

SELECT evergreen.upgrade_deps_block_check('1351', :eg_version);

INSERT INTO permission.perm_list ( id, code, description )
    VALUES (
        641,
        'ADMIN_FUND_ROLLOVER',
        oils_i18n_gettext(
            641,
            'Allow a user to perform fund propagation and rollover',
            'ppl',
            'description'
        )
    );

-- ensure that permission groups that are able to
-- rollover funds can continue to do so
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('ADMIN_FUND_ROLLOVER'))
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map
        
        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)
            
        --- Anybody who can view resources should also see reservations
        --- at the same level
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'ADMIN_FUND'
        );

COMMIT;
