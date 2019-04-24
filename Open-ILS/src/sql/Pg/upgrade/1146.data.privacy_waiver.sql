BEGIN;

SELECT evergreen.upgrade_deps_block_check('1146', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
    VALUES (
        'circ.privacy_waiver',
        oils_i18n_gettext('circ.privacy_waiver',
            'Allow others to use patron account (privacy waiver)',
            'coust', 'label'),
        oils_i18n_gettext('circ.privacy_waiver',
            'Add a note to a user account indicating that specified people are allowed to ' ||
            'place holds, pick up holds, check out items, or view borrowing history for that user account',
            'coust', 'description'),
        'circ',
        'bool'
    );

COMMIT;

