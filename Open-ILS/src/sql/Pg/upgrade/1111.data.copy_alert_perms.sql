BEGIN;

SELECT evergreen.upgrade_deps_block_check('1111', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 594, 'ADMIN_COPY_ALERT_TYPE', oils_i18n_gettext( 594,
    'Administer copy alert types', 'ppl', 'description' )),
 ( 595, 'CREATE_COPY_ALERT_TYPE', oils_i18n_gettext( 595,
    'Create copy alert types', 'ppl', 'description' )),
 ( 596, 'UPDATE_COPY_ALERT_TYPE', oils_i18n_gettext( 596,
    'Update copy alert types', 'ppl', 'description' )),
 ( 597, 'DELETE_COPY_ALERT_TYPE', oils_i18n_gettext( 597,
    'Delete copy alert types', 'ppl', 'description' )),
 ( 598, 'ADMIN_COPY_ALERT_SUPPRESS', oils_i18n_gettext( 598,
    'Administer copy alert suppression', 'ppl', 'description' )),
 ( 599, 'CREATE_COPY_ALERT_SUPPRESS', oils_i18n_gettext( 599,
    'Create copy alert suppression', 'ppl', 'description' )),
 ( 600, 'UPDATE_COPY_ALERT_SUPPRESS', oils_i18n_gettext( 600,
    'Update copy alert suppression', 'ppl', 'description' )),
 ( 601, 'DELETE_COPY_ALERT_SUPPRESS', oils_i18n_gettext( 601,
    'Delete copy alert suppression', 'ppl', 'description' )),
 ( 602, 'ADMIN_COPY_ALERT', oils_i18n_gettext( 602,
    'Administer copy alerts', 'ppl', 'description' )),
 ( 603, 'CREATE_COPY_ALERT', oils_i18n_gettext( 603,
    'Create copy alerts', 'ppl', 'description' )),
 ( 604, 'VIEW_COPY_ALERT', oils_i18n_gettext( 604,
    'View copy alerts', 'ppl', 'description' )),
 ( 605, 'UPDATE_COPY_ALERT', oils_i18n_gettext( 605,
    'Update copy alerts', 'ppl', 'description' )),
 ( 606, 'DELETE_COPY_ALERT', oils_i18n_gettext( 606,
    'Delete copy alerts', 'ppl', 'description' ))
;

COMMIT;

