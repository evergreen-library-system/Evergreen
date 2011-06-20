-- Evergreen DB patch 0555.unnest_oils_xpath_table.sql
--
-- Replace usage of custom explode_array() function with native unnest()
--
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0555'); -- dbs

CREATE OR REPLACE FUNCTION oils_xpath_table ( key TEXT, document_field TEXT, relation_name TEXT, xpaths TEXT, criteria TEXT ) RETURNS SETOF RECORD AS $func$
DECLARE
    xpath_list  TEXT[];
    select_list TEXT[];
    where_list  TEXT[];
    q           TEXT;
    out_record  RECORD;
    empty_test  RECORD;
BEGIN
    xpath_list := STRING_TO_ARRAY( xpaths, '|' );

    select_list := ARRAY_APPEND( select_list, key || '::INT AS key' );

    FOR i IN 1 .. ARRAY_UPPER(xpath_list,1) LOOP
        IF xpath_list[i] = 'null()' THEN
            select_list := ARRAY_APPEND( select_list, 'NULL::TEXT AS c_' || i );
        ELSE
            select_list := ARRAY_APPEND(
                select_list,
                $sel$
                unnest(
                    COALESCE(
                        NULLIF(
                            oils_xpath(
                                $sel$ ||
                                    quote_literal(
                                        CASE
                                            WHEN xpath_list[i] ~ $re$/[^/[]*@[^/]+$$re$ OR xpath_list[i] ~ $re$text\(\)$$re$ THEN xpath_list[i]
                                            ELSE xpath_list[i] || '//text()'
                                        END
                                    ) ||
                                $sel$,
                                $sel$ || document_field || $sel$
                            ),
                           '{}'::TEXT[]
                        ),
                        '{NULL}'::TEXT[]
                    )
                ) AS c_$sel$ || i
            );
            where_list := ARRAY_APPEND(
                where_list,
                'c_' || i || ' IS NOT NULL'
            );
        END IF;
    END LOOP;

    q := $q$
SELECT * FROM (
    SELECT $q$ || ARRAY_TO_STRING( select_list, ', ' ) || $q$ FROM $q$ || relation_name || $q$ WHERE ($q$ || criteria || $q$)
)x WHERE $q$ || ARRAY_TO_STRING( where_list, ' OR ' );
    -- RAISE NOTICE 'query: %', q;

    FOR out_record IN EXECUTE q LOOP
        RETURN NEXT out_record;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

COMMIT;
