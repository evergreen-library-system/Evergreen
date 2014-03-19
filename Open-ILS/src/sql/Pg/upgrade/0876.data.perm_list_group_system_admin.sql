BEGIN;

SELECT evergreen.upgrade_deps_block_check('0876', :eg_version);

INSERT INTO permission.perm_list ( code, description ) VALUES
 ( 'group_application.user.staff.admin.system_admin', oils_i18n_gettext( '',
    'Allow a user to add/remove users to/from the "System Administrator" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.cat_admin', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Cataloging Administrator" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.circ_admin', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Circulation Administrator" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.data_review', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Data Review" group', 'ppl', 'description' )),
 ( 'group_application.user.staff.volunteers', oils_i18n_gettext( '', 
    'Allow a user to add/remove users to/from the "Volunteers" group', 'ppl', 'description' ))
;

COMMIT;
