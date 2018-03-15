BEGIN;
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE permission.grp_tree_display_entry (
    id      SERIAL PRIMARY KEY,
    position INTEGER NOT NULL,
    org     INTEGER NOT NULL REFERENCES actor.org_unit (id)
            DEFERRABLE INITIALLY DEFERRED,
    grp     INTEGER NOT NULL REFERENCES permission.grp_tree (id)
            DEFERRABLE INITIALLY DEFERRED,
    disabled BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pgtde_once_per_org UNIQUE (org, grp)
);

ALTER TABLE permission.grp_tree_display_entry
    ADD COLUMN parent integer REFERENCES permission.grp_tree_display_entry (id)
            DEFERRABLE INITIALLY DEFERRED;
            
COMMIT;