BEGIN;

SELECT evergreen.upgrade_deps_block_check('0970', :eg_version); -- Dyrcona/gmcharlt

CREATE OR REPLACE FUNCTION search.facets_for_record_set(ignore_facet_classes TEXT[], hits BIGINT[]) RETURNS TABLE (id INT, value TEXT, count BIGINT) AS $$
    SELECT id, value, count FROM (
        SELECT mfae.field AS id,
               mfae.value,
               COUNT(DISTINCT mmrsm.source),
               row_number() OVER (
                PARTITION BY mfae.field ORDER BY COUNT(distinct mmrsm.source) DESC
               ) AS rownum
        FROM metabib.facet_entry mfae
        JOIN metabib.metarecord_source_map mmrsm ON (mfae.source = mmrsm.source)
        JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
        WHERE mmrsm.source IN (SELECT * FROM unnest($2))
        AND cmf.facet_field
        AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
        GROUP by 1, 2
    ) all_facets
    WHERE rownum <= (SELECT COALESCE((SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled), 1000));
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.facets_for_metarecord_set(ignore_facet_classes TEXT[], hits BIGINT[]) RETURNS TABLE (id INT, value TEXT, count BIGINT) AS $$
    SELECT id, value, count FROM (
        SELECT mfae.field AS id,
               mfae.value,
               COUNT(DISTINCT mmrsm.metarecord),
               row_number() OVER (
                PARTITION BY mfae.field ORDER BY COUNT(distinct mmrsm.metarecord) DESC
               ) AS rownum
        FROM metabib.facet_entry mfae
        JOIN metabib.metarecord_source_map mmrsm ON (mfae.source = mmrsm.source)
        JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
        WHERE mmrsm.metarecord IN (SELECT * FROM unnest($2))
        AND cmf.facet_field
        AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
        GROUP by 1, 2
    ) all_facets
    WHERE rownum <= (SELECT COALESCE((SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled), 1000));
$$ LANGUAGE SQL;

COMMIT;
