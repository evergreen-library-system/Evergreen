BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0581'); -- tsbere via miker

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.opac_renewal.use_original_circ_lib',
        oils_i18n_gettext(
            'circ.opac_renewal.use_original_circ_lib',
            'Circ: Use original circulation library on opac renewal instead of user home library',
            'cgf',
            'label'
        ),
        FALSE
    );

COMMIT;

