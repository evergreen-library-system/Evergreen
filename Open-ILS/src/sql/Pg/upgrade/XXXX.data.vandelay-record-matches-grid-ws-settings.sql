BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.vandelay.queue.bib.record_matches', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.vandelay.queue.bib.record_matches',
        'Grid Config: cat.vandelay.queue.bib.record_matches',
        'cwst', 'label'
    )
);

COMMIT;
