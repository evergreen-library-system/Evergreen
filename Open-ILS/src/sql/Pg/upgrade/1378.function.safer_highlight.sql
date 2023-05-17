BEGIN;

SELECT evergreen.upgrade_deps_block_check('1378', :eg_version);

CREATE OR REPLACE FUNCTION search.highlight_display_fields(
    rid         BIGINT,
    tsq_map     TEXT, -- '(a | b) & c' => '1,2,3,4', ...
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    tsq         TEXT;
    fields      TEXT;
    afields     INT[];
    seen        INT[];
BEGIN

    FOR tsq, fields IN SELECT key, value FROM each(tsq_map::HSTORE) LOOP
        SELECT  ARRAY_AGG(unnest::INT) INTO afields
          FROM  unnest(regexp_split_to_array(fields,','));
        seen := seen || afields;

        RETURN QUERY
            SELECT * FROM search.highlight_display_fields_impl(
                rid, tsq, afields, css_class, hl_all,minwords,
                maxwords, shortwords, maxfrags, delimiter
            );
    END LOOP;

    RETURN QUERY
        SELECT  id,
                source,
                field,
                evergreen.escape_for_html(value) AS value,
                evergreen.escape_for_html(value) AS highlight
          FROM  metabib.display_entry
          WHERE source = rid
                AND NOT (field = ANY (seen));
END;
$f$ LANGUAGE PLPGSQL ROWS 10;

COMMIT;

