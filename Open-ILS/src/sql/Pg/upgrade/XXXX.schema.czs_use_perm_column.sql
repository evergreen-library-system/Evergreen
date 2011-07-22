-- Evergreen DB patch XXXX.schema.czs_use_perm_column.sql
--
-- This adds a column to config.z3950_source called use_perm.
-- The idea is that if a permission is set for a given source,
-- then staff will need the referenced permission to use that
-- source.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE config.z3950_source 
    ADD COLUMN use_perm INT REFERENCES permission.perm_list (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

COMMENT ON COLUMN config.z3950_source.use_perm IS $$
If set, this permission is required for the source to be listed in the staff
client Z39.50 interface.  Similar to permission.grp_tree.application_perm.
$$;

COMMIT;
