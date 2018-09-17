BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.print.config.default', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.default',
        'Print config for default context',
        'cwst', 'label'
    )
), (
    'eg.print.config.receipt', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.receipt',
        'Print config for receipt context',
        'cwst', 'label'
    )
), (
    'eg.print.config.label', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.label',
        'Print config for label context',
        'cwst', 'label'
    )
), (
    'eg.print.config.mail', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.mail',
        'Print config for mail context',
        'cwst', 'label'
    )
), (
    'eg.print.config.offline', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.offline',
        'Print config for offline context',
        'cwst', 'label'
    )
);

COMMIT;
