BEGIN;

SELECT evergreen.upgrade_deps_block_check('0757', :eg_version);

SET search_path = public, pg_catalog;

DO $$
DECLARE
lang TEXT;
BEGIN
FOR lang IN SELECT substring(pptsd.dictname from '(.*)_stem$') AS lang FROM pg_catalog.pg_ts_dict pptsd JOIN pg_catalog.pg_namespace ppn ON ppn.oid = pptsd.dictnamespace
WHERE ppn.nspname = 'pg_catalog' AND pptsd.dictname LIKE '%_stem' LOOP
RAISE NOTICE 'FOUND LANGUAGE %', lang;

EXECUTE 'DROP TEXT SEARCH DICTIONARY IF EXISTS ' || lang || '_nostop CASCADE;
CREATE TEXT SEARCH DICTIONARY ' || lang || '_nostop (TEMPLATE=pg_catalog.snowball, language=''' || lang || ''');
COMMENT ON TEXT SEARCH DICTIONARY ' || lang || '_nostop IS ''' ||lang || ' snowball stemmer with no stopwords for ASCII words only.'';
CREATE TEXT SEARCH CONFIGURATION ' || lang || '_nostop ( COPY = pg_catalog.' || lang || ' );
ALTER TEXT SEARCH CONFIGURATION ' || lang || '_nostop ALTER MAPPING FOR word, hword, hword_part WITH pg_catalog.simple;
ALTER TEXT SEARCH CONFIGURATION ' || lang || '_nostop ALTER MAPPING FOR asciiword, asciihword, hword_asciipart WITH ' || lang || '_nostop;';

END LOOP;
END;
$$;
CREATE TEXT SEARCH CONFIGURATION keyword ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION "default" ( COPY = english_nostop );

SET search_path = evergreen, public, pg_catalog;

ALTER TABLE config.metabib_class
    ADD COLUMN a_weight NUMERIC  DEFAULT 1.0 NOT NULL,
    ADD COLUMN b_weight NUMERIC  DEFAULT 0.4 NOT NULL,
    ADD COLUMN c_weight NUMERIC  DEFAULT 0.2 NOT NULL,
    ADD COLUMN d_weight NUMERIC  DEFAULT 0.1 NOT NULL;

CREATE TABLE config.ts_config_list (
    id      TEXT PRIMARY KEY,
    name    TEXT NOT NULL
);
COMMENT ON TABLE config.ts_config_list IS $$
Full Text Configs

A list of full text configs with names and descriptions.
$$;

CREATE TABLE config.metabib_class_ts_map (
    id              SERIAL PRIMARY KEY,
    field_class     TEXT NOT NULL REFERENCES config.metabib_class (name),
    ts_config       TEXT NOT NULL REFERENCES config.ts_config_list (id),
    active          BOOL NOT NULL DEFAULT TRUE,
    index_weight    CHAR(1) NOT NULL DEFAULT 'C' CHECK (index_weight IN ('A','B','C','D')),
    index_lang      TEXT NULL,
    search_lang     TEXT NULL,
    always          BOOL NOT NULL DEFAULT true
);
COMMENT ON TABLE config.metabib_class_ts_map IS $$
Text Search Configs for metabib class indexing

This table contains text search config definitions for
storing index_vector values.
$$;

CREATE TABLE config.metabib_field_ts_map (
    id              SERIAL PRIMARY KEY,
    metabib_field   INT NOT NULL REFERENCES config.metabib_field (id),
    ts_config       TEXT NOT NULL REFERENCES config.ts_config_list (id),
    active          BOOL NOT NULL DEFAULT TRUE,
    index_weight    CHAR(1) NOT NULL DEFAULT 'C' CHECK (index_weight IN ('A','B','C','D')),
    index_lang      TEXT NULL,
    search_lang     TEXT NULL
);
COMMENT ON TABLE config.metabib_field_ts_map IS $$
Text Search Configs for metabib field indexing

This table contains text search config definitions for
storing index_vector values.
$$;

CREATE TABLE metabib.combined_identifier_field_entry (
    record          BIGINT      NOT NULL,
    metabib_field   INT         NULL,
    index_vector    tsvector    NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_identifier_field_entry_fakepk_idx ON metabib.combined_identifier_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_identifier_field_entry_index_vector_idx ON metabib.combined_identifier_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_identifier_field_source_idx ON metabib.combined_identifier_field_entry (metabib_field);

CREATE TABLE metabib.combined_title_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_title_field_entry_fakepk_idx ON metabib.combined_title_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_title_field_entry_index_vector_idx ON metabib.combined_title_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_title_field_source_idx ON metabib.combined_title_field_entry (metabib_field);

CREATE TABLE metabib.combined_author_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_author_field_entry_fakepk_idx ON metabib.combined_author_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_author_field_entry_index_vector_idx ON metabib.combined_author_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_author_field_source_idx ON metabib.combined_author_field_entry (metabib_field);

CREATE TABLE metabib.combined_subject_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_subject_field_entry_fakepk_idx ON metabib.combined_subject_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_subject_field_entry_index_vector_idx ON metabib.combined_subject_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_subject_field_source_idx ON metabib.combined_subject_field_entry (metabib_field);

CREATE TABLE metabib.combined_keyword_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_keyword_field_entry_fakepk_idx ON metabib.combined_keyword_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_keyword_field_entry_index_vector_idx ON metabib.combined_keyword_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_keyword_field_source_idx ON metabib.combined_keyword_field_entry (metabib_field);

CREATE TABLE metabib.combined_series_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_series_field_entry_fakepk_idx ON metabib.combined_series_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_series_field_entry_index_vector_idx ON metabib.combined_series_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_series_field_source_idx ON metabib.combined_series_field_entry (metabib_field);

CREATE OR REPLACE FUNCTION metabib.update_combined_index_vectors(bib_id BIGINT) RETURNS VOID AS $func$
BEGIN
    DELETE FROM metabib.combined_keyword_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_keyword_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.keyword_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_keyword_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.keyword_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_title_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_title_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.title_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_title_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.title_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_author_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_author_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.author_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_author_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.author_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_subject_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_subject_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.subject_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_subject_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.subject_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_series_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.series_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.series_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_identifier_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_identifier_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.identifier_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_identifier_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.identifier_field_entry WHERE source = bib_id;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.
            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = ind_data.value;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES
                    (metabib.browse_normalize(ind_data.value, ind_data.field));
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field AND NOT skip_search THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    IF NOT skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS evergreen.oils_tsearch2() CASCADE;
DROP FUNCTION IF EXISTS public.oils_tsearch2() CASCADE;

CREATE OR REPLACE FUNCTION public.oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
    temp_vector     TEXT := '';
    ts_rec          RECORD;
    cur_weight      "char";
BEGIN
    value := NEW.value;
    NEW.index_vector = ''::tsvector;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
        NEW.value = value;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN
        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
        value := public.search_normalize(value);
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    ELSIF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR ts_rec IN
            SELECT ts_config, index_weight
            FROM config.metabib_class_ts_map
            WHERE field_class = TG_ARGV[0]
                AND index_lang IS NULL OR EXISTS (SELECT 1 FROM metabib.record_attr WHERE id = NEW.source AND index_lang IN(attrs->'item_lang',attrs->'language'))
                AND always OR NOT EXISTS (SELECT 1 FROM config.metabib_field_ts_map WHERE metabib_field = NEW.field)
            UNION
            SELECT ts_config, index_weight
            FROM config.metabib_field_ts_map
            WHERE metabib_field = NEW.field
               AND index_lang IS NULL OR EXISTS (SELECT 1 FROM metabib.record_attr WHERE id = NEW.source AND index_lang IN(attrs->'item_lang',attrs->'language'))
            ORDER BY index_weight ASC
        LOOP
            IF cur_weight IS NOT NULL AND cur_weight != ts_rec.index_weight THEN
                NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
                temp_vector = '';
            END IF;
            cur_weight = ts_rec.index_weight;
            SELECT INTO temp_vector temp_vector || ' ' || to_tsvector(ts_rec.ts_config::regconfig, value)::TEXT;
        END LOOP;
        NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
    ELSE
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER authority_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.full_rec
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER authority_simple_heading_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.simple_heading
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.identifier_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('identifier');

CREATE TRIGGER metabib_title_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.title_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('title');

CREATE TRIGGER metabib_author_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.author_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('author');

CREATE TRIGGER metabib_subject_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.subject_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('subject');

CREATE TRIGGER metabib_keyword_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.keyword_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER metabib_series_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.series_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('series');

CREATE TRIGGER metabib_browse_entry_fti_trigger
    BEFORE INSERT OR UPDATE ON metabib.browse_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER metabib_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.real_full_rec
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('default');

INSERT INTO config.ts_config_list(id, name) VALUES
    ('simple','Non-Stemmed Simple'),
    ('danish_nostop','Danish Stemmed'),
    ('dutch_nostop','Dutch Stemmed'),
    ('english_nostop','English Stemmed'),
    ('finnish_nostop','Finnish Stemmed'),
    ('french_nostop','French Stemmed'),
    ('german_nostop','German Stemmed'),
    ('hungarian_nostop','Hungarian Stemmed'),
    ('italian_nostop','Italian Stemmed'),
    ('norwegian_nostop','Norwegian Stemmed'),
    ('portuguese_nostop','Portuguese Stemmed'),
    ('romanian_nostop','Romanian Stemmed'),
    ('russian_nostop','Russian Stemmed'),
    ('spanish_nostop','Spanish Stemmed'),
    ('swedish_nostop','Swedish Stemmed'),
    ('turkish_nostop','Turkish Stemmed');

INSERT INTO config.metabib_class_ts_map(field_class, ts_config, index_weight, always) VALUES
    ('keyword','simple','A',true),
    ('keyword','english_nostop','C',true),
    ('title','simple','A',true),
    ('title','english_nostop','C',true),
    ('author','simple','A',true),
    ('author','english_nostop','C',true),
    ('series','simple','A',true),
    ('series','english_nostop','C',true),
    ('subject','simple','A',true),
    ('subject','english_nostop','C',true),
    ('identifier','simple','A',true);

CREATE OR REPLACE FUNCTION evergreen.rel_bump(terms TEXT[], value TEXT, bumps TEXT[], mults NUMERIC[]) RETURNS NUMERIC AS
$BODY$
use strict;
my ($terms,$value,$bumps,$mults) = @_;

my $retval = 1;

for (my $id = 0; $id < @$bumps; $id++) {
        if ($bumps->[$id] eq 'first_word') {
                $retval *= $mults->[$id] if ($value =~ /^$terms->[0]/);
        } elsif ($bumps->[$id] eq 'full_match') {
                my $fullmatch = join(' ', @$terms);
                $retval *= $mults->[$id] if ($value =~ /^$fullmatch$/);
        } elsif ($bumps->[$id] eq 'word_order') {
                my $wordorder = join('.*', @$terms);
                $retval *= $mults->[$id] if ($value =~ /$wordorder/);
        }
}
return $retval;
$BODY$ LANGUAGE plperlu IMMUTABLE STRICT COST 100;

UPDATE metabib.identifier_field_entry set value = value;
UPDATE metabib.title_field_entry set value = value;
UPDATE metabib.author_field_entry set value = value;
UPDATE metabib.subject_field_entry set value = value;
UPDATE metabib.keyword_field_entry set value = value;
UPDATE metabib.series_field_entry set value = value;

SELECT metabib.update_combined_index_vectors(id)
    FROM biblio.record_entry
    WHERE NOT deleted;

COMMIT;
