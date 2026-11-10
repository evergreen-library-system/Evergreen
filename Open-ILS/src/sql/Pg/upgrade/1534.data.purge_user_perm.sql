BEGIN;

SELECT evergreen.upgrade_deps_block_check('1534', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES
(697, 'PURGE_USER', oils_i18n_gettext(697,
    'Allow a user to delete (purge) another user', 'ppl', 'description'));

-- Grant the PURGE_USER permission to any group that has DELETE_USER.
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('PURGE_USER'))
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map

        /* Don't add the permission if it's already assigned. I'm
        not sure if that's possible, but it seems we usually check
        for this in upgrade scripts like this, so here we go. */
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)

        -- Add the permission to any group that has DELETE_USER
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'DELETE_USER'
        );

COMMIT;
