BEGIN;

SELECT evergreen.upgrade_deps_block_check('1427', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.conjoined', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.conjoined',
        'Grid Config: catalog.record.conjoined',
        'cwst', 'label'
    )
);

COMMIT;
