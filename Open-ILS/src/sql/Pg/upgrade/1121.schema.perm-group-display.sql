BEGIN;
SELECT evergreen.upgrade_deps_block_check('1121', :eg_version);

CREATE TABLE permission.grp_tree_display_entry (
    id      SERIAL PRIMARY KEY,
    position INTEGER NOT NULL,
    org     INTEGER NOT NULL REFERENCES actor.org_unit (id)
            DEFERRABLE INITIALLY DEFERRED,
    grp     INTEGER NOT NULL REFERENCES permission.grp_tree (id)
            DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT pgtde_once_per_org UNIQUE (org, grp)
);

ALTER TABLE permission.grp_tree_display_entry
    ADD COLUMN parent integer REFERENCES permission.grp_tree_display_entry (id)
            DEFERRABLE INITIALLY DEFERRED;

INSERT INTO permission.perm_list (id, code, description)
VALUES (609, 'MANAGE_CUSTOM_PERM_GRP_TREE', oils_i18n_gettext( 609,
    'Allows a user to manage custom permission group lists.', 'ppl', 'description' ));
            
COMMIT;
