BEGIN;

--SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'acq.lineitem.sort_order', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.sort_order',
        'ACQ Lineitem List Sort Order',
        'cwst', 'label'
    )
);

COMMIT;
