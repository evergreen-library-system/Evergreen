BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.edi_attr_set', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.admin.acq.edi_attr_set',
        'EDI Attribute Sets Grid Settings',
        'cwst', 'label'
    )
);

COMMIT;
