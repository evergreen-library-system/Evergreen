BEGIN;

SELECT evergreen.upgrade_deps_block_check('0692', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
    VALUES (
        'circ.fines.charge_when_closed',
         oils_i18n_gettext(
            'circ.fines.charge_when_closed',
            'Charge fines on overdue circulations when closed',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.fines.charge_when_closed',
            'Normally, fines are not charged when a library is closed.  When set to True, fines will be charged during scheduled closings and normal weekly closed days.',
            'coust',
            'description'
        ),
        'circ',
        'bool'
    );

COMMIT;
