-- Evergreen DB patch XXXX.data.ou_setting_generate_overdue_on_lost.sql.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0567', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'circ.lost.generate_overdue_on_checkin',
    oils_i18n_gettext( 
        'circ.lost.generate_overdue_on_checkin',
        'Circ:  Lost Checkin Generates New Overdues',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'circ.lost.generate_overdue_on_checkin',
        'Enabling this setting causes retroactive creation of not-yet-existing overdue fines on lost item checkin, up to the point of checkin time (or max fines is reached).  This is different than "restore overdue on lost", because it only creates new overdue fines.  Use both settings together to get the full complement of overdue fines for a lost item',
        'coust',
        'label'
    ),
    'bool'
);

COMMIT;
