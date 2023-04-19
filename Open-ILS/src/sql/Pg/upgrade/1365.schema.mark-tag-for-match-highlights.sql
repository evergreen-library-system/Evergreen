BEGIN;

SELECT evergreen.upgrade_deps_block_check('1365', :eg_version);

CREATE OR REPLACE FUNCTION search.highlight_display_fields_impl(
    rid         BIGINT,
    tsq         TEXT,
    field_list  INT[] DEFAULT '{}'::INT[],
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    opts            TEXT := '';
    v_css_class     TEXT := css_class;
    v_delimiter     TEXT := delimiter;
    v_field_list    INT[] := field_list;
    hl_query        TEXT;
BEGIN
    IF v_delimiter LIKE $$%'%$$ OR v_delimiter LIKE '%"%' THEN --"
        v_delimiter := ' ... ';
    END IF;

    IF NOT hl_all THEN
        opts := opts || 'MinWords=' || minwords;
        opts := opts || ', MaxWords=' || maxwords;
        opts := opts || ', ShortWords=' || shortwords;
        opts := opts || ', MaxFragments=' || maxfrags;
        opts := opts || ', FragmentDelimiter="' || delimiter || '"';
    ELSE
        opts := opts || 'HighlightAll=TRUE';
    END IF;

    IF v_css_class LIKE $$%'%$$ OR v_css_class LIKE '%"%' THEN -- "
        v_css_class := 'oils_SH';
    END IF;

    opts := opts || $$, StopSel=</mark>, StartSel="<mark class='$$ || v_css_class; -- "

    IF v_field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO v_field_list FROM config.metabib_field WHERE display_field;
    END IF;

    hl_query := $$
        SELECT  de.id,
                de.source,
                de.field,
                evergreen.escape_for_html(de.value) AS value,
                ts_headline(
                    ts_config::REGCONFIG,
                    evergreen.escape_for_html(de.value),
                    $$ || quote_literal(tsq) || $$,
                    $1 || ' ' || mf.field_class || ' ' || mf.name || $xx$'>"$xx$ -- "'
                ) AS highlight
          FROM  metabib.display_entry de
                JOIN config.metabib_field mf ON (mf.id = de.field)
                JOIN search.best_tsconfig t ON (t.id = de.field)
          WHERE de.source = $2
                AND field = ANY ($3)
          ORDER BY de.id;$$;

    RETURN QUERY EXECUTE hl_query USING opts, rid, v_field_list;
END;
$f$ LANGUAGE PLPGSQL;

COMMIT;
