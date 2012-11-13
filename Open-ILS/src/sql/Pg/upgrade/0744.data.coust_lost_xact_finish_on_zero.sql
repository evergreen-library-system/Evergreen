BEGIN;

SELECT evergreen.upgrade_deps_block_check('0744', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.lost.xact_open_on_zero',
        'finance',
        oils_i18n_gettext(
            'circ.lost.xact_open_on_zero',
            'Leave transaction open when lost balance equals zero',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.lost.xact_open_on_zero',
            'Leave transaction open when lost balance equals zero.  This leaves the lost copy on the patron record when it is paid',
            'coust',
            'description'
        ),
        'bool'
    );

COMMIT;
