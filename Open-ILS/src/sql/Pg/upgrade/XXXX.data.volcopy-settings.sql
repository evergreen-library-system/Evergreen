
INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.cat.volcopy.defaults', 'cat', 'object',
    oils_i18n_gettext(
        'eg.cat.volcopy.defaults',
        'Holdings Editor Default Values and Visibility',
        'cwst', 'label'
    )
), (
    'cat.copy.templates', 'cat', 'object',
    oils_i18n_gettext(
        'cat.copy.templates',
        'Holdings Editor Copy Templates',
        'cwst', 'label'
    )
);


