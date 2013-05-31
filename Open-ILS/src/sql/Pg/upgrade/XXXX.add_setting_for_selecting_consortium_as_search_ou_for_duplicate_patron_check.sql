BEGIN;

    SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

    INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype ) VALUES (
        'opac.duplicate_patron_check_use_consortium', 'opac',
            oils_i18n_gettext(
                'opac.duplicate_patron_check_use_consortium',
                'Use consortium as the search ou for the duplicate patron check.',
                'coust',
                'label'),
            oils_i18n_gettext(
                'opac.duplicate_patron_check_use_consortium',
                'When using the patron registration page, the duplicate patron check will use the consortium as the search_ou.',
                'coust',
                'description'),
            'bool'
    );

    INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES (
            1, 'opac.duplicate_patron_check_use_consortium', 'true'
    );

COMMIT;
