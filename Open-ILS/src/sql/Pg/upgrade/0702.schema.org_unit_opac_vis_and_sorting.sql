BEGIN;

SELECT evergreen.upgrade_deps_block_check('0702', :eg_version);

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

ALTER TABLE actor.org_unit ADD COLUMN 
    sibling_order INTEGER NOT NULL DEFAULT 0; 

ALTER TABLE auditor.actor_org_unit_history ADD COLUMN 
    sibling_order INTEGER NOT NULL DEFAULT 0;

COMMIT;

/* UNDO
BEGIN;
DELETE FROM config.global_flag WHERE name = 'opac.org_unit.non_inheritied_visibility';
ALTER TABLE actor.org_unit DROP COLUMN sibling_order;
ALTER TABLE auditor.actor_org_unit_history DROP COLUMN sibling_order;
COMMIT;
*/

