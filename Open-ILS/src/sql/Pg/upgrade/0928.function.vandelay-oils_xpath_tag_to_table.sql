BEGIN;

SELECT evergreen.upgrade_deps_block_check('0928', :eg_version);

CREATE OR REPLACE FUNCTION oils_xpath_tag_to_table(marc text, tag text, xpaths text[]) RETURNS SETOF record AS $function$

-- This function currently populates columns with the FIRST matching value
-- of each XPATH.  It would be reasonable to add a 'return_arrays' option
-- where each column is an array of all matching values for each path, but
-- that remains as a TODO

DECLARE
    field RECORD;
    output RECORD;
    select_list TEXT[];
    from_list TEXT[];
    q TEXT;
BEGIN
    -- setup query select
    FOR i IN 1 .. ARRAY_UPPER(xpaths,1) LOOP
        IF xpaths[i] = 'null()' THEN
            select_list := ARRAY_APPEND(select_list, 'NULL::TEXT AS c_' || i );
        ELSE
            select_list := ARRAY_APPEND(select_list, '(oils_xpath(' ||
                quote_literal(
                    CASE
                        WHEN xpaths[i] ~ $re$/[^/[]*@[^/]+$$re$ -- attribute
                            OR xpaths[i] ~ $re$text\(\)$$re$
                        THEN xpaths[i]
                        ELSE xpaths[i] || '//text()'
                    END
                ) || ', field_marc))[1] AS cl_' || i);
                -- hardcoded to first value for each path
        END IF;
    END LOOP;

    -- run query over tag set
    q := 'SELECT ' || ARRAY_TO_STRING(select_list, ',')
        || ' FROM UNNEST(oils_xpath(' || quote_literal('//*[@tag="' || tag
        || '"]') || ', ' || quote_literal(marc) || ')) AS field_marc;';
    --RAISE NOTICE '%', q;

    RETURN QUERY EXECUTE q;
END;

$function$ LANGUAGE PLPGSQL;

COMMIT;
