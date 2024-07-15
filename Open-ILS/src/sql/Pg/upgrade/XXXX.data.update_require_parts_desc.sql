BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.org_unit_setting_type 
SET description = oils_i18n_gettext('circ.holds.ui_require_monographic_part_when_present',
        'Normally the selection of a monographic part during hold placement is optional if there is at least one copy on the bib without a monographic part.  A true value for this setting will require part selection even under this condition.  A true value for this setting will also require a part to be added before saving any changes or creating a new item in the holdings editor, if there are parts on the bib.',
        'coust', 'description')
WHERE name = 'circ.holds.ui_require_monographic_part_when_present';

COMMIT;
