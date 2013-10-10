BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0843', :eg_version);

-- this upgrade file serves 2 purposes:
-- 1) add ON UPDATE CASCADE for those upgrading 2_5/master
-- 2) alter config.z3950_index_field_map for those upgrading from 2_4 and previous (other lines
--    are no-ops in this case)
ALTER TABLE config.metabib_search_alias DROP CONSTRAINT metabib_search_alias_field_fkey;
ALTER TABLE config.z3950_index_field_map DROP CONSTRAINT z3950_index_field_map_metabib_field_fkey;
ALTER TABLE metabib.browse_entry_def_map DROP CONSTRAINT browse_entry_def_map_def_fkey;

ALTER TABLE config.metabib_search_alias ADD CONSTRAINT metabib_search_alias_field_fkey FOREIGN KEY (field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.z3950_index_field_map ADD CONSTRAINT z3950_index_field_map_metabib_field_fkey FOREIGN KEY (metabib_field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.browse_entry_def_map ADD CONSTRAINT browse_entry_def_map_def_fkey FOREIGN KEY (def) REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
