--Upgrade Script for 3.5.3 to 3.5.4
\set eg_version '''3.5.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.5.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1248', :eg_version);

DO LANGUAGE plpgsql $$
DECLARE
  ind RECORD;
  tablist TEXT;
BEGIN

  -- We only want to mess with gist indexes in stock Evergreen.
  -- If you've added your own convert them or don't as you see fit.
  PERFORM
  FROM pg_index idx
    JOIN pg_class cls ON cls.oid=idx.indexrelid
    JOIN pg_namespace sc ON sc.oid = cls.relnamespace
    JOIN pg_class tab ON tab.oid=idx.indrelid
    JOIN pg_attribute at ON (at.attnum = ANY(idx.indkey) AND at.attrelid = tab.oid)
    JOIN pg_am am ON am.oid=cls.relam
  WHERE am.amname = 'gist'
    AND cls.relname IN (
      'authority_full_rec_index_vector_idx',
      'authority_simple_heading_index_vector_idx',
      'metabib_identifier_field_entry_index_vector_idx',
      'metabib_combined_identifier_field_entry_index_vector_idx',
      'metabib_title_field_entry_index_vector_idx',
      'metabib_combined_title_field_entry_index_vector_idx',
      'metabib_author_field_entry_index_vector_idx',
      'metabib_combined_author_field_entry_index_vector_idx',
      'metabib_subject_field_entry_index_vector_idx',
      'metabib_combined_subject_field_entry_index_vector_idx',
      'metabib_keyword_field_entry_index_vector_idx',
      'metabib_combined_keyword_field_entry_index_vector_idx',
      'metabib_series_field_entry_index_vector_idx',
      'metabib_combined_series_field_entry_index_vector_idx',
      'metabib_full_rec_index_vector_idx'
    );

  IF NOT FOUND THEN
    RETURN;
  END IF;
  
  tablist := '';
  
  RAISE NOTICE 'Converting GIST indexes into GIN indexes...';

  FOR ind IN SELECT sc.nspname AS sch, tab.relname AS tab, cls.relname AS idx, at.attname AS col
             FROM pg_index idx
               JOIN pg_class cls ON cls.oid=idx.indexrelid
               JOIN pg_namespace sc ON sc.oid = cls.relnamespace
               JOIN pg_class tab ON tab.oid=idx.indrelid
               JOIN pg_attribute at ON (at.attnum = ANY(idx.indkey) AND at.attrelid = tab.oid)
               JOIN pg_am am ON am.oid=cls.relam
             WHERE am.amname = 'gist'
               AND cls.relname IN (
                 'authority_full_rec_index_vector_idx',
                 'authority_simple_heading_index_vector_idx',
                 'metabib_identifier_field_entry_index_vector_idx',
                 'metabib_combined_identifier_field_entry_index_vector_idx',
                 'metabib_title_field_entry_index_vector_idx',
                 'metabib_combined_title_field_entry_index_vector_idx',
                 'metabib_author_field_entry_index_vector_idx',
                 'metabib_combined_author_field_entry_index_vector_idx',
                 'metabib_subject_field_entry_index_vector_idx',
                 'metabib_combined_subject_field_entry_index_vector_idx',
                 'metabib_keyword_field_entry_index_vector_idx',
                 'metabib_combined_keyword_field_entry_index_vector_idx',
                 'metabib_series_field_entry_index_vector_idx',
                 'metabib_combined_series_field_entry_index_vector_idx',
                 'metabib_full_rec_index_vector_idx'
               )
  LOOP
    -- Move existing index out of the way so there's no difference between new databases and upgraded databases
    EXECUTE FORMAT('ALTER INDEX %I.%I RENAME TO %I_gist', ind.sch, ind.idx, ind.idx);

    -- Meet the new index, same as the old index (almost)
    EXECUTE FORMAT('CREATE INDEX %I ON %I.%I USING GIN (%I)', ind.idx, ind.sch, ind.tab, ind.col);

    -- And drop the old index
    EXECUTE FORMAT('DROP INDEX %I.%I_gist', ind.sch, ind.idx);

    tablist := tablist || '           ' || ind.sch || '.' || ind.tab || E'\n';

  END LOOP;

  RAISE NOTICE E'Conversion Complete.\n\n           You should run a VACUUM ANALYZE on the following tables soon:\n%', tablist;

END $$;



SELECT evergreen.upgrade_deps_block_check('1258', :eg_version);

UPDATE config.metabib_field 
SET xpath =  '//*[@tag=''260'' or @tag=''264''][1]'
WHERE id = 52 AND xpath = '//*[@tag=''260'']';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
