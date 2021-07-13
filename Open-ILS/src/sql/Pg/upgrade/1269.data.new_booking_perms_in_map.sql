BEGIN;

SELECT evergreen.upgrade_deps_block_check('1269', :eg_version);

WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('VIEW_BOOKING_RESERVATION', 'VIEW_BOOKING_RESERVATION_ATTR_MAP'))

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
                WHERE code = 'VIEW_BOOKING_RESOURCE'
        );


COMMIT;
