-- Evergreen DB patch 0703.tpac_value_maps.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0703', :eg_version);

ALTER TABLE config.coded_value_map
    ADD COLUMN opac_visible BOOL NOT NULL DEFAULT TRUE,
    ADD COLUMN search_label TEXT,
    ADD COLUMN is_simple BOOL NOT NULL DEFAULT FALSE;

COMMIT;
