BEGIN;

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    IF NEW.label_class IS NULL THEN
            NEW.label_class := COALESCE(
            (   
                SELECT substring(value from E'\\d+')::integer
                FROM actor.org_unit_ancestor_setting('cat.default_classification_scheme', NEW.owning_lib)
            ), 1
        );
    END IF;

    EXECUTE FORMAT('SELECT %s(%L)', acnc.normalizer::REGPROC, NEW.label)
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;
    NEW.label_sortkey = sortkey;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS public.extract_marc_field(TEXT, BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.extract_marc_field(TEXT, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION evergreen.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    query := FORMAT($q$
        SELECT  regexp_replace(
                    oils_xpath_string(
                        %L,
                        marc,
                        ' '
                    ),
                    %L,
                    '',
                    'g')
          FROM %s
          WHERE id = %L
    $q$, $3, $4, $1::REGCLASS, $2);

    EXECUTE query INTO output;

    -- RAISE NOTICE 'query: %, output; %', query, output;

    RETURN output;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
    SELECT extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL IMMUTABLE;

DROP FUNCTION IF EXISTS unapi.memoize(TEXT, BIGINT, TEXT, TEXT, TEXT[], TEXT, INT, HSTORE, HSTORE, BOOL);

COMMIT;
