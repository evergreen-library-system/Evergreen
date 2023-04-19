BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1364', :eg_version);

-- 950.data.seed-values.sql

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 642, 'UPDATE_COPY_BARCODE', oils_i18n_gettext(642,
    'Update the barcode for an item.', 'ppl', 'description'))
;

-- give this perm to perm groups that already have UPDATE_COPY
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('UPDATE_COPY_BARCODE'))
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
                WHERE code = 'UPDATE_COPY'
        );

COMMIT;
