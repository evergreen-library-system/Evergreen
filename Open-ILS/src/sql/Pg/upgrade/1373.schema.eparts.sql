BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1373', :eg_version);

-- 950.data.seed-values.sql

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'circ.holds.api_require_monographic_part_when_present',
    NULL,
    FALSE,
    oils_i18n_gettext(
        'circ.holds.api_require_monographic_part_when_present',
        'Holds: Require Monographic Part When Present for hold check.',
        'cgf', 'label'
    )
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.holds.ui_require_monographic_part_when_present',
    oils_i18n_gettext('circ.holds.ui_require_monographic_part_when_present',
        'Require Monographic Part when Present',
        'coust', 'label'),
    'circ',
    oils_i18n_gettext('circ.holds.ui_require_monographic_part_when_present',
        'Normally the selection of a monographic part during hold placement is optional if there is at least one copy on the bib without a monographic part.  A true value for this setting will require part selection even under this condition.',
        'coust', 'description'),
    'bool'
);

COMMIT;
