BEGIN;

SELECT evergreen.upgrade_deps_block_check('0969', :eg_version); -- jeffdavis/stompro

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('org.restrict_opt_to_depth',
         'sec',
         oils_i18n_gettext('org.restrict_opt_to_depth',
            'Restrict patron opt-in to home library and related orgs at specified depth',
            'coust', 'label'),
         oils_i18n_gettext('org.restrict_opt_to_depth',
            'Patrons at this library can only be opted-in at org units which are within the '||
            'library''s section of the org tree, at or below the depth specified by this setting. '||
            'They cannot be opted in at any other libraries.',
            'coust', 'description'),
        'integer');

COMMIT;

