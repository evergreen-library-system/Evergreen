BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0380'); -- dbs

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('cat.label.font.size',
            oils_i18n_gettext('cat.label.font.size',
                'Cataloging: Spine and pocket label font size', 'coust', 'label'),
            oils_i18n_gettext('cat.label.font.size',
                'Set the default font size for spine and pocket labels', 'coust', 'description'),
            'integer'
        )
        ,('cat.label.font.family',
            oils_i18n_gettext('cat.label.font.family',
                'Cataloging: Spine and pocket label font family', 'coust', 'label'),
            oils_i18n_gettext('cat.label.font.family',
                'Set the preferred font family for spine and pocket labels. You can specify a list of fonts, separated by commas, in order of preference; the system will use the first font it finds with a matching name. For example, "Arial, Helvetica, serif".',
                'coust', 'description'),
            'string'
        )
        ,('cat.spine.line.width',
            oils_i18n_gettext('cat.spine.line.width',
                'Cataloging: Spine label line width', 'coust', 'label'),
            oils_i18n_gettext('cat.spine.line.width',
                'Set the default line width for spine labels in number of characters. This specifies the boundary at which lines must be wrapped.',
                'coust', 'description'),
            'integer'
        )
        ,('cat.spine.line.height',
            oils_i18n_gettext('cat.spine.line.height',
                'Cataloging: Spine label maximum lines', 'coust', 'label'),
            oils_i18n_gettext('cat.spine.line.height',
                'Set the default maximum number of lines for spine labels.',
                'coust', 'description'),
            'integer'
        )
        ,('cat.spine.line.margin',
            oils_i18n_gettext('cat.spine.line.margin',
                'Cataloging: Spine label left margin', 'coust', 'label'),
            oils_i18n_gettext('cat.spine.line.margin',
                'Set the left margin for spine labels in number of characters.',
                'coust', 'description'),
            'integer'
        )
;

INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES
    (1, 'cat.spine.line.margin', 0)
    ,(1, 'cat.spine.line.height', 9)
    ,(1, 'cat.spine.line.width', 8)
    ,(1, 'cat.label.font.family', '"monospace"')
    ,(1, 'cat.label.font.size', 10)
;

COMMIT;
