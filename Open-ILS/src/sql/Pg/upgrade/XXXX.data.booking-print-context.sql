
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.print.template_context.booking_capture', 'gui', 'string',
    oils_i18n_gettext(
        'eg.print.template_context.booking_capture',
        'Print Template Context: booking_capture',
        'cwst', 'label'
    )
);

COMMIT;
