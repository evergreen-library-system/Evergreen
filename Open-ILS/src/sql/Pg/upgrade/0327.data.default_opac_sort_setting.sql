BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0327'); 

INSERT INTO config.usr_setting_type (name, opac_visible, label, description, datatype) 
    VALUES (
        'opac.default_sort',
        TRUE,
        oils_i18n_gettext(
            'opac.default_sort',
            'OPAC Default Search Sort',
            'cust',
            'label'
        ),
        oils_i18n_gettext(
            'opac.default_sort',
            'OPAC Default Search Sort',
            'cust',
            'description'
        ),
        'string'
    );

COMMIT;

