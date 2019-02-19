BEGIN;

SELECT evergreen.upgrade_deps_block_check('1151', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.cat.vandelay.import.templates', 'cat', 'object',
    oils_i18n_gettext(
        'eg.cat.vandelay.import.templates',
        'Vandelay Import Form Templates',
        'cwst', 'label'
    )
);

COMMIT;
