BEGIN;

SELECT evergreen.upgrade_deps_block_check('0940', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.pg_statistics (tab TEXT, col TEXT) RETURNS TABLE(element TEXT, frequency INT) AS $$
BEGIN
    -- This query will die on PG < 9.2, but the function can be created. We just won't use it where we can't.
    RETURN QUERY
        SELECT  e,
                f
          FROM  (SELECT ROW_NUMBER() OVER (),
                        (f * 100)::INT AS f
                  FROM  (SELECT UNNEST(most_common_elem_freqs) AS f
                          FROM  pg_stats
                          WHERE tablename = tab
                                AND attname = col
                        )x
                ) AS f
                JOIN (SELECT ROW_NUMBER() OVER (),
                             e
                       FROM (SELECT UNNEST(most_common_elems::text::text[]) AS e
                              FROM  pg_stats 
                              WHERE tablename = tab
                                    AND attname = col
                            )y
                ) AS elems USING (row_number);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.query_int_wrapper (INT[],TEXT) RETURNS BOOL AS $$
BEGIN
    RETURN $1 @@ $2::query_int;
END;
$$ LANGUAGE PLPGSQL STABLE;

COMMIT;

