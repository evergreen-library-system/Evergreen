INSERT INTO config.org_unit_setting_type(name, grp, label, description, datatype) VALUES

( 'circ.grace.extend', 'circ',
    oils_i18n_gettext('circ.grace.extend',
        'Auto-Extend Grace Periods',
        'coust', 'label'),
    oils_i18n_gettext('circ.grace.extend',
        'When enabled grace periods will auto-extend. By default this will be only when they are a full day or more and end on a closed date, though other options can alter this.',
        'coust', 'description'),
    'bool', null)

,( 'circ.grace.extend.all', 'circ',
    oils_i18n_gettext('circ.grace.extend.all',
        'Auto-Extending Grace Periods extend for all closed dates',
        'coust', 'label'),
    oils_i18n_gettext('circ.grace.extend.all',
        'If enabled and Grace Periods auto-extending is turned on grace periods will extend past all closed dates they intersect, within hard-coded limits. This basically becomes "grace periods can only be consumed by closed dates".',
        'coust', 'description'),
    'bool', null)

,( 'circ.grace.extend.into_closed', 'circ',
    oils_i18n_gettext('circ.grace.extend.into_closed',
        'Auto-Extending Grace Periods include trailing closed dates',
        'coust', 'label'),
    oils_i18n_gettext('circ.grace.extend.into_closed',
         'If enabled and Grace Periods auto-extending is turned on grace periods will include closed dates that directly follow the last day of the grace period, to allow a backdate into the closed dates to assume "returned after hours on the last day of the grace period, and thus still within it" automatically.',
        'coust', 'description'),
    'bool', null);
