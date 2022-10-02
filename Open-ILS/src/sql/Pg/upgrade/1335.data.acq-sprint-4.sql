BEGIN;

SELECT evergreen.upgrade_deps_block_check('1335', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'acq.lineitem.sort_order', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.sort_order',
        'ACQ Lineitem List Sort Order',
        'cwst', 'label'
    )
);

INSERT INTO config.org_unit_setting_type (name, grp, datatype, label)
VALUES (
    'ui.staff.acq.show_deprecated_links', 'gui', 'bool',
    oils_i18n_gettext(
        'ui.staff.acq.show_deprecated_links',
        'Display Links to Deprecated Acquisitions Interfaces',
        'cwst', 'label'
    )
);

COMMIT;
