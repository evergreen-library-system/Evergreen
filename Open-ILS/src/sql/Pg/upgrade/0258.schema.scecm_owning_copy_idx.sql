BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0258'); -- Galen Charlton

-- resolves performance issue noted by EG Indiana

CREATE INDEX scecm_owning_copy_idx ON asset.stat_cat_entry_copy_map(owning_copy);

COMMIT;
