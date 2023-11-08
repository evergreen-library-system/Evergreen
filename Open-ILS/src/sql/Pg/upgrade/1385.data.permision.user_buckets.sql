BEGIN;

SELECT evergreen.upgrade_deps_block_check('1385', :eg_version); -- mmorgan, rfrasur, tmccanna

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 645, 'ADMIN_USER_BUCKET', oils_i18n_gettext(645,
    'Allow a user to administer User Buckets', 'ppl', 'description'));
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 646, 'CREATE_USER_BUCKET', oils_i18n_gettext(646,
    'Allow a user to create a User Bucket', 'ppl', 'description'));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Circulators' AND
                aout.name = 'System' AND
                perm.code IN (
                        'ADMIN_USER_BUCKET',
                        'CREATE_USER_BUCKET');

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Circulation Administrator' AND
                aout.name = 'System' AND
                perm.code IN (
                        'ADMIN_USER_BUCKET',
                        'CREATE_USER_BUCKET');

COMMIT;
