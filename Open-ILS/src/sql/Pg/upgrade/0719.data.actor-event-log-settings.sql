BEGIN;

SELECT evergreen.upgrade_deps_block_check('0719', :eg_version);

INSERT INTO config.org_unit_setting_type (
    name, label, grp, description, datatype
) VALUES (
    'circ.staff.max_visible_event_age',
    'Maximum visible age of User Trigger Events in Staff Interfaces',
    'circ',
    'If this is unset, staff can view User Trigger Events regardless of age. When this is set to an interval, it represents the age of the oldest possible User Trigger Event that can be viewed.',
    'interval'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.actor.user.event_log',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.actor.user.event_log',
        'User Event Log',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.actor.user.event_log',
        'User Event Log Saved Column Settings',
        'cust',
        'description'
    ),
    'string'
);

INSERT INTO permission.perm_list ( id, code, description )
    VALUES (
        535,
        'VIEW_TRIGGER_EVENT',
        oils_i18n_gettext(
            535,
            'Allows a user to view circ- and hold-related action/trigger events',
            'ppl',
            'description'
        )
    );

COMMIT;
