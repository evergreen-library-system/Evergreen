BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0169'); -- phasefx

-- Effective undoes 0117.data.org-setting-notes-require-initials.sql
-- At the time of this script, these shouldn't be in any production systems, so I'm removing, not "upgrading".
DELETE FROM actor.org_unit_setting WHERE name IN (
    'ui.circ_and_cat.notes.require_initials',
    'ui.circ.standing_penalty.require_initials'
);
DELETE FROM config.org_unit_setting_type WHERE name IN (
    'ui.circ_and_cat.notes.require_initials',
    'ui.circ.standing_penalty.require_initials'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    SELECT DISTINCT
        'ui.staff.require_initials',
        oils_i18n_gettext(
            'ui.staff.require_initials', 
            'GUI: Require staff initials for entry/edit of item/patron/penalty notes/messages.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'ui.staff.require_initials', 
            'Appends staff initials and edit date into note content.', 
            'coust', 
            'description'),
        'bool'
    FROM config.org_unit_setting_type -- Since this script is way after the setting was introduced, being careful
    WHERE NOT EXISTS (SELECT 1 FROM config.org_unit_setting_type WHERE name = 'ui.staff.require_initials');

COMMIT;
