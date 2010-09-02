BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0381'); -- dbs

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('cat.label.font.weight',
            oils_i18n_gettext('cat.label.font.weight',
                'Cataloging: Spine and pocket label font weight', 'coust', 'label'),
            oils_i18n_gettext('cat.label.font.weight',
                'Set the preferred font weight for spine and pocket labels. You can specify "normal", "bold", "bolder", or "lighter".',
                'coust', 'description'),
            'string'
        )
;

INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES
    (1, 'cat.label.font.weight', '"normal"')
;

COMMIT;
