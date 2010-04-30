BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0249');

INSERT INTO config.global_flag (name, label) -- defaults to enabled=FALSE
    VALUES (
        'cat.bib.use_id_for_tcn',
        oils_i18n_gettext(
            'cat.bib.use_id_for_tcn',
            'Cat: Use Internal ID for TCN Value',
            'cgf', 
            'label'
        )
    );

COMMIT;
