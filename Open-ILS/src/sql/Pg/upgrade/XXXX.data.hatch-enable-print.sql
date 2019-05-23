BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.hatch.enable.printing', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.hatch.enable.printing',
        'Use Hatch for printing',
        'cwst', 'label'
    )
);

ALTER TABLE actor.workstation_setting
    ADD CONSTRAINT ws_once_per_key UNIQUE (workstation, name);

COMMIT;


