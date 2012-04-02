-- Evergreen DB patch 0701.schema.patron_stat_category_enhancements.sql
--
-- Enables users to set patron statistical categories as required,
-- whether or not users can input free text for the category value.
-- Enables administrators to set an entry as the default for any
-- given patron statistical category and org unit.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0701', :eg_version);

-- New table

CREATE TABLE actor.stat_cat_entry_default (
    id              SERIAL  PRIMARY KEY,
    stat_cat_entry  INT     NOT NULL REFERENCES actor.stat_cat_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    stat_cat        INT     NOT NULL REFERENCES actor.stat_cat (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT sced_once_per_owner UNIQUE (stat_cat,owner)
);

COMMENT ON TABLE actor.stat_cat_entry_default IS $$
User Statistical Category Default Entry

A library may choose one of the stat_cat entries to be the
default entry.
$$;

-- Add columns to existing tables

-- Patron stat cat required column
ALTER TABLE actor.stat_cat
    ADD COLUMN required BOOL NOT NULL DEFAULT FALSE;

-- Patron stat cat allow_freetext column
ALTER TABLE actor.stat_cat
    ADD COLUMN allow_freetext BOOL NOT NULL DEFAULT TRUE;

-- Add permissions

INSERT INTO permission.perm_list ( id, code, description ) VALUES
    ( 525, 'CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT', oils_i18n_gettext( 525, 
        'User may set a default entry in a patron statistical category', 'ppl', 'description' )),
    ( 526, 'UPDATE_PATRON_STAT_CAT_ENTRY_DEFAULT', oils_i18n_gettext( 526, 
        'User may reset a default entry in a patron statistical category', 'ppl', 'description' )),
    ( 527, 'DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT', oils_i18n_gettext( 527, 
        'User may unset a default entry in a patron statistical category', 'ppl', 'description' ));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, TRUE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Circulation Administrator' AND
        aout.name = 'System' AND
        perm.code IN ('CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT', 'DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT');

COMMIT;
