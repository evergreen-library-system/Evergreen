BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- Per Lp bug 1684984, the config.internal_flag,
-- ingest.disable_metabib_field_entry, was made obsolete by the
-- addition of the ingest.skip_browse_indexing,
-- ingest.skip_search_indexing, and ingest.skip_facet_indexing flags.
-- Since it is not used in the database, we delete it.
DELETE FROM config.internal_flag
WHERE name = 'ingest.disable_metabib_field_entry';

COMMIT;
