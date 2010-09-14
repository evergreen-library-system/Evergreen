BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0394'); -- gmc

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class )
SELECT DISTINCT
    'cat.default_classification_scheme',
    oils_i18n_gettext(
        'cat.default_classification_scheme',
        'Cataloging: Default Classification Scheme',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'cat.default_classification_scheme',
        'Defines the default classification scheme for new call numbers: 1 = Generic; 2 = Dewey; 3 = LC',
        'coust',
        'descripton'
        ),
    'link',
    'acnc'
FROM config.org_unit_setting_type
WHERE NOT EXISTS (SELECT 1 FROM config.org_unit_setting_type WHERE name = 'cat.default_classification_scheme');

COMMIT;
