-- Evergreen DB patch 0859.data.staff-initials-settings.sql
--
-- More granular configuration settings for requiring use of staff initials
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0859', :eg_version);

-- add new granular settings for requiring use of staff initials
INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.staff.require_initials.patron_standing_penalty',
        'gui',
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_standing_penalty',
            'Require staff initials for entry/edit of patron standing penalties and messages.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_standing_penalty',
            'Appends staff initials and edit date into patron standing penalties and messages.',
            'coust',
            'description'
        ),
        'bool'
    ), (
        'ui.staff.require_initials.patron_info_notes',
        'gui',
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_info_notes',
            'Require staff initials for entry/edit of patron notes.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.staff.require_initials.patron_info_notes',
            'Appends staff initials and edit date into patron note content.',
            'coust',
            'description'
        ),
        'bool'
    ), (
        'ui.staff.require_initials.copy_notes',
        'gui',
        oils_i18n_gettext(
            'ui.staff.require_initials.copy_notes',
            'Require staff initials for entry/edit of copy notes.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.staff.require_initials.copy_notes',
            'Appends staff initials and edit date into copy note content..',
            'coust',
            'description'
        ),
        'bool'
    );

-- Update any existing setting so that the original set value is now passed to
-- one of the newer settings.

UPDATE actor.org_unit_setting
SET name = 'ui.staff.require_initials.patron_standing_penalty'
WHERE name = 'ui.staff.require_initials';

-- Add similar values for new settings as old ones to preserve existing configured
-- functionality.

INSERT INTO actor.org_unit_setting (org_unit, name, value)
SELECT org_unit, 'ui.staff.require_initials.patron_info_notes', value
FROM actor.org_unit_setting
WHERE name = 'ui.staff.require_initials.patron_standing_penalty';

INSERT INTO actor.org_unit_setting (org_unit, name, value)
SELECT org_unit, 'ui.staff.require_initials.copy_notes', value
FROM actor.org_unit_setting
WHERE name = 'ui.staff.require_initials.patron_standing_penalty';

-- Update setting logs so that the original setting name's history is now transferred
-- over to one of the newer settings.

UPDATE config.org_unit_setting_type_log
SET field_name = 'ui.staff.require_initials.patron_standing_penalty'
WHERE field_name = 'ui.staff.require_initials';

-- Remove the old setting entirely

DELETE FROM config.org_unit_setting_type WHERE name = 'ui.staff.require_initials';

COMMIT;
