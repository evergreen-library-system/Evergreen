INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 516, 'CREATE_REPORT_TEMPLATE', oils_i18n_gettext( 516,
    'Allows a user to create report templates', 'ppl', 'description' ));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, 516, depth, grantable
        FROM permission.grp_perm_map
        WHERE perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'RUN_REPORTS'
        );
