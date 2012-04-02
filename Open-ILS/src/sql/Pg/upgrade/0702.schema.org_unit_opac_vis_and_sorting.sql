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

CREATE TYPE actor.org_unit_custom_tree_purpose AS ENUM ('opac');

CREATE TABLE actor.org_unit_custom_tree (
    id              SERIAL  PRIMARY KEY,
    active          BOOLEAN DEFAULT FALSE,
    purpose         actor.org_unit_custom_tree_purpose NOT NULL DEFAULT 'opac' UNIQUE
);

CREATE TABLE actor.org_unit_custom_tree_node (
    id              SERIAL  PRIMARY KEY,
    tree            INTEGER REFERENCES actor.org_unit_custom_tree (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit        INTEGER NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	parent_node     INTEGER REFERENCES actor.org_unit_custom_tree_node (id) DEFERRABLE INITIALLY DEFERRED,
    sibling_order   INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT aouctn_once_per_org UNIQUE (tree, org_unit)
);
    

COMMIT;

/* UNDO
BEGIN;
DELETE FROM config.global_flag WHERE name = 'opac.org_unit.non_inheritied_visibility';
DROP TABLE actor.org_unit_custom_tree_node;
DROP TABLE actor.org_unit_custom_tree;
DROP TYPE actor.org_unit_custom_tree_purpose;
COMMIT;
*/

