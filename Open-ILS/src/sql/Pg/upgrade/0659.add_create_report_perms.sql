-- Evergreen DB patch 0659.add_create_report_perms.sql
--
-- Add a permission to control the ability to create report templates
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0659', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
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


COMMIT;
