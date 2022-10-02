BEGIN;

SELECT evergreen.upgrade_deps_block_check('1334', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.acq.picklist.upload.templates','acq','object',
    oils_i18n_gettext(
        'eg.acq.picklist.upload.templates',
        'Acq Picklist Uploader Templates',
        'cwst','label'
    )
);

COMMIT;
