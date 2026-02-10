BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.circ.patron.nav.collapse', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.nav.collapse',
        'Collapse Patron Navigation Display',
        'cwst', 'label'
    )
);

COMMIT;
