-- Evergreen DB patch 0693.schema.do_not_despace_issns.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0693', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
-- Delete the index normalizer that was meant to remove spaces from ISSNs
-- but ended up breaking records with multiple ISSNs
DELETE FROM config.metabib_field_index_norm_map WHERE id IN (
    SELECT map.id FROM config.metabib_field_index_norm_map map
        INNER JOIN config.metabib_field cmf ON cmf.id = map.field
        INNER JOIN config.index_normalizer cin ON cin.id = map.norm
    WHERE cin.func = 'replace'
        AND cmf.field_class = 'identifier'
        AND cmf.name = 'issn'
        AND map.params = $$[" ",""]$$
);

-- Reindex records that have more than just a single ISSN
-- to ensure that spaces are maintained
SELECT metabib.reingest_metabib_field_entries(source)
  FROM metabib.identifier_field_entry mife
    INNER JOIN config.metabib_field cmf ON cmf.id = mife.field
  WHERE cmf.field_class = 'identifier'
    AND cmf.name = 'issn'
    AND char_length(value) > 9
;


COMMIT;
