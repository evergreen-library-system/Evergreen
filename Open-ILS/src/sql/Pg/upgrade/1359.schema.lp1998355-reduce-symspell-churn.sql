BEGIN;

SELECT evergreen.upgrade_deps_block_check('1359', :eg_version);

CREATE OR REPLACE FUNCTION search.symspell_dictionary_reify () RETURNS SETOF search.symspell_dictionary AS $f$
 WITH new_rows AS (
    DELETE FROM search.symspell_dictionary_updates WHERE transaction_id = txid_current() RETURNING *
 ), computed_rows AS ( -- this collapses the rows deleted into the format we need for UPSERT
    SELECT  SUM(keyword_count)    AS keyword_count,
            SUM(title_count)      AS title_count,
            SUM(author_count)     AS author_count,
            SUM(subject_count)    AS subject_count,
            SUM(series_count)     AS series_count,
            SUM(identifier_count) AS identifier_count,

            prefix_key,

            ARRAY_REMOVE(ARRAY_AGG(DISTINCT keyword_suggestions[1]), NULL)    AS keyword_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT title_suggestions[1]), NULL)      AS title_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT author_suggestions[1]), NULL)     AS author_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT subject_suggestions[1]), NULL)    AS subject_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT series_suggestions[1]), NULL)     AS series_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT identifier_suggestions[1]), NULL) AS identifier_suggestions
      FROM  new_rows
      GROUP BY prefix_key
 )
 INSERT INTO search.symspell_dictionary AS d SELECT * FROM computed_rows
 ON CONFLICT (prefix_key) DO UPDATE SET
    keyword_count = GREATEST(0, d.keyword_count + EXCLUDED.keyword_count),
    keyword_suggestions = evergreen.text_array_merge_unique(EXCLUDED.keyword_suggestions,d.keyword_suggestions),

    title_count = GREATEST(0, d.title_count + EXCLUDED.title_count),
    title_suggestions = evergreen.text_array_merge_unique(EXCLUDED.title_suggestions,d.title_suggestions),

    author_count = GREATEST(0, d.author_count + EXCLUDED.author_count),
    author_suggestions = evergreen.text_array_merge_unique(EXCLUDED.author_suggestions,d.author_suggestions),

    subject_count = GREATEST(0, d.subject_count + EXCLUDED.subject_count),
    subject_suggestions = evergreen.text_array_merge_unique(EXCLUDED.subject_suggestions,d.subject_suggestions),

    series_count = GREATEST(0, d.series_count + EXCLUDED.series_count),
    series_suggestions = evergreen.text_array_merge_unique(EXCLUDED.series_suggestions,d.series_suggestions),

    identifier_count = GREATEST(0, d.identifier_count + EXCLUDED.identifier_count),
    identifier_suggestions = evergreen.text_array_merge_unique(EXCLUDED.identifier_suggestions,d.identifier_suggestions)

    WHERE (
        EXCLUDED.keyword_count <> 0 OR
        EXCLUDED.title_count <> 0 OR
        EXCLUDED.author_count <> 0 OR
        EXCLUDED.subject_count <> 0 OR
        EXCLUDED.series_count <> 0 OR
        EXCLUDED.identifier_count <> 0 OR
        NOT (EXCLUDED.keyword_suggestions <@ d.keyword_suggestions) OR
        NOT (EXCLUDED.title_suggestions <@ d.title_suggestions) OR
        NOT (EXCLUDED.author_suggestions <@ d.author_suggestions) OR
        NOT (EXCLUDED.subject_suggestions <@ d.subject_suggestions) OR
        NOT (EXCLUDED.series_suggestions <@ d.series_suggestions) OR
        NOT (EXCLUDED.identifier_suggestions <@ d.identifier_suggestions)
    )
 RETURNING *;
$f$ LANGUAGE SQL;

COMMIT;
