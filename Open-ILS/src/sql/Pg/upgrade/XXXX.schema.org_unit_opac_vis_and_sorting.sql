BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.global_flag (name, enabled, label) 
    VALUES (
        'opac.org_unit.non_inheritied_visibility',
        FALSE,
        oils_i18n_gettext(
            'opac.org_unit.non_inheritied_visibility',
            'Org Units Do Not Inherit Visibility',
            'cgf',
            'label'
        )
    );

COMMIT;

/* UNDO
BEGIN;
DELETE FROM config.global_flag WHERE name = 'opac.org_unit.non_inheritied_visibility';
COMMIT;
*/

