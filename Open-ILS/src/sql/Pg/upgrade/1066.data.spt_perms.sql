BEGIN;

SELECT evergreen.upgrade_deps_block_check('1066', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 593, 'ADMIN_SERIAL_PATTERN_TEMPLATE', oils_i18n_gettext( 593,
    'Administer serial prediction pattern templates', 'ppl', 'description' ))
;

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, FALSE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Serials' AND
        aout.name = 'System' AND
        perm.code IN (
            'ADMIN_SERIAL_PATTERN_TEMPLATE'
        );

COMMIT;
