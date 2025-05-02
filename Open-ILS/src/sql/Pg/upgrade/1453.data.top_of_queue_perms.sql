BEGIN;

SELECT evergreen.upgrade_deps_block_check('1453', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   676,
   'UPDATE_TOP_OF_QUEUE',
   oils_i18n_gettext(676,
     'Allow setting and unsetting hold from top of hold queue (cut in line)', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'UPDATE_TOP_OF_QUEUE');


--Assign permission to any perm groups with UPDATE_HOLD_REQUEST_TIME
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('UPDATE_TOP_OF_QUEUE'))
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map

        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)

        --- we're going to match the depth of their existing perm
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'UPDATE_HOLD_REQUEST_TIME'
        );

COMMIT;