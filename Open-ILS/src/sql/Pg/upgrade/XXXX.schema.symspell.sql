BEGIN;

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

INSERT INTO config.internal_flag (name, value, enabled) VALUES ('symspell.prefix_length', '6', TRUE);
INSERT INTO config.internal_flag (name, value, enabled) VALUES ('symspell.max_edit_distance', '3', TRUE);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'opac.did_you_mean.max_suggestions', 'opac',
   oils_i18n_gettext(
     'opac.did_you_mean.max_suggestions',
     'Maximum number of spelling suggestions that may be offered',
     'coust', 'label'),
   oils_i18n_gettext(
     'opac.did_you_mean.max_suggestions',
     'If set to -1, provide "best" suggestion if mispelled; if set higher than 0, the maximum suggestions that can be provided; if set to 0, disable suggestions.',
     'coust', 'description'),
   'integer' );

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'opac.did_you_mean.low_result_threshold', 'opac',
   oils_i18n_gettext(
     'opac.did_you_mean.low_result_threshold',
     'Maximum search result count at which spelling suggestions may be offered',
     'coust', 'label'),
   oils_i18n_gettext(
     'opac.did_you_mean.low_result_threshold',
     'If a search results in this number or fewer results, and there are correctable spelling mistakes, a suggested search may be provided.',
     'coust', 'description'),
   'integer' );

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'search.symspell.min_suggestion_use_threshold', 'opac',
   oils_i18n_gettext(
     'search.symspell.min_suggestion_use_threshold',
     'Minimum required uses of a spelling suggestions that may be offered',
     'coust', 'label'),
   oils_i18n_gettext(
     'search.symspell.min_suggestion_use_threshold',
     'The number of bibliographic records (more or less) that a spelling suggestion must appear in to be considered before offering it to a user. Defaults to 1 (must appear in the bib data).',
     'coust', 'description'),
   'integer' );

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'search.symspell.soundex.weight', 'opac',
   oils_i18n_gettext(
     'search.symspell.soundex.weight',
     'Soundex score weighting in OPAC spelling suggestions.',
     'coust', 'label'),
   oils_i18n_gettext(
     'search.symspell.soundex.weight',
     'Soundex, trgm, and keyboard distance similarity measures can be combined to form a secondary ordering parameter for spelling suggestions. This controls the relative weight of the scaled soundex component. Defaults to 0 for "off".',
     'coust', 'description'),
   'integer' );

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'search.symspell.pg_trgm.weight', 'opac',
   oils_i18n_gettext(
     'search.symspell.pg_trgm.weight',
     'Pg_trgm score weighting in OPAC spelling suggestions.',
     'coust', 'label'),
   oils_i18n_gettext(
     'search.symspell.pg_trgm.weight',
     'Soundex, pg_trgm, and keyboard distance similarity measures can be combined to form a secondary ordering parameter for spelling suggestions. This controls the relative weight of the scaled pg_trgm component. Defaults to 0 for "off".',
     'coust', 'description'),
   'integer' );

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'search.symspell.keyboard_distance.weight', 'opac',
   oils_i18n_gettext(
     'search.symspell.keyboard_distance.weight',
     'Keyboard distance score weighting in OPAC spelling suggestions.',
     'coust', 'label'),
   oils_i18n_gettext(
     'search.symspell.keyboard_distance.weight',
     'Soundex, trgm, and keyboard distance similarity measures can be combined to form a secondary ordering parameter for spelling suggestions. This controls the relative weight of the scaled keyboard distance component. Defaults to 0 for "off".',
     'coust', 'description'),
   'integer' );

CREATE OR REPLACE FUNCTION evergreen.uppercase( TEXT ) RETURNS TEXT AS $$
    return uc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.text_array_merge_unique (
    TEXT[], TEXT[]
) RETURNS TEXT[] AS $F$
    SELECT NULLIF(ARRAY(
        SELECT * FROM UNNEST($1) x WHERE x IS NOT NULL
            UNION
        SELECT * FROM UNNEST($2) y WHERE y IS NOT NULL
    ),'{}');
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION evergreen.qwerty_keyboard_distance ( a TEXT, b TEXT ) RETURNS NUMERIC AS $F$
use String::KeyboardDistance qw(:all);
return qwerty_keyboard_distance(@_);
$F$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.qwerty_keyboard_distance_match ( a TEXT, b TEXT ) RETURNS NUMERIC AS $F$
use String::KeyboardDistance qw(:all);
return qwerty_keyboard_distance_match(@_);
$F$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.levenshtein_damerau_edistance ( a TEXT, b TEXT, INT ) RETURNS NUMERIC AS $F$
use Text::Levenshtein::Damerau::XS qw/xs_edistance/;
return xs_edistance(@_);
$F$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE TABLE search.symspell_dictionary (
    keyword_count           INT     NOT NULL DEFAULT 0,
    title_count             INT     NOT NULL DEFAULT 0,
    author_count            INT     NOT NULL DEFAULT 0,
    subject_count           INT     NOT NULL DEFAULT 0,
    series_count            INT     NOT NULL DEFAULT 0,
    identifier_count        INT     NOT NULL DEFAULT 0,

    prefix_key              TEXT    PRIMARY KEY,

    keyword_suggestions     TEXT[],
    title_suggestions       TEXT[],
    author_suggestions      TEXT[],
    subject_suggestions     TEXT[],
    series_suggestions      TEXT[],
    identifier_suggestions  TEXT[]
) WITH (fillfactor = 80);

CREATE OR REPLACE FUNCTION search.symspell_parse_words ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT UNNEST(x) FROM regexp_matches($1, '([[:alnum:]]+''*[[:alnum:]]*)', 'g') x;
$F$ LANGUAGE SQL STRICT IMMUTABLE;

-- This version does not preserve input word order!
CREATE OR REPLACE FUNCTION search.symspell_parse_words_distinct ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT DISTINCT UNNEST(x) FROM regexp_matches($1, '([[:alnum:]]+''*[[:alnum:]]*)', 'g') x;
$F$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_transfer_casing ( withCase TEXT, withoutCase TEXT )
RETURNS TEXT AS $F$
DECLARE
    woChars TEXT[];
    curr    TEXT;
    ind     INT := 1;
BEGIN
    woChars := regexp_split_to_array(withoutCase,'');
    FOR curr IN SELECT x FROM regexp_split_to_table(withCase, '') x LOOP
        IF curr = evergreen.uppercase(curr) THEN
            woChars[ind] := evergreen.uppercase(woChars[ind]);
        END IF;
        ind := ind + 1;
    END LOOP;
    RETURN ARRAY_TO_STRING(woChars,'');
END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_generate_edits (
    raw_word    TEXT,
    dist        INT DEFAULT 1,
    maxED       INT DEFAULT 3
) RETURNS TEXT[] AS $F$
DECLARE
    item    TEXT;
    list    TEXT[] := '{}';
    sublist TEXT[] := '{}';
BEGIN
    FOR I IN 1 .. CHARACTER_LENGTH(raw_word) LOOP
        item := SUBSTRING(raw_word FROM 1 FOR I - 1) || SUBSTRING(raw_word FROM I + 1);
        IF NOT list @> ARRAY[item] THEN
            list := item || list;
            IF dist < maxED AND CHARACTER_LENGTH(raw_word) > dist + 1 THEN
                sublist := search.symspell_generate_edits(item, dist + 1, maxED) || sublist;
            END IF;
        END IF;
    END LOOP;

    IF dist = 1 THEN
        RETURN evergreen.text_array_merge_unique(list, sublist);
    ELSE
        RETURN list || sublist;
    END IF;
END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

-- DROP TYPE search.symspell_lookup_output CASCADE;
CREATE TYPE search.symspell_lookup_output AS (
    suggestion          TEXT,
    suggestion_count    INT,
    lev_distance        INT,
    pg_trgm_sim         NUMERIC,
    qwerty_kb_match     NUMERIC,
    soundex_sim         NUMERIC,
    input               TEXT,
    norm_input          TEXT,
    prefix_key          TEXT,
    prefix_key_count    INT,
    word_pos            INT
);

CREATE OR REPLACE FUNCTION search.symspell_lookup (
    raw_input       TEXT,
    search_class    TEXT,
    verbosity       INT DEFAULT 2,
    xfer_case       BOOL DEFAULT FALSE,
    count_threshold INT DEFAULT 1,
    soundex_weight  INT DEFAULT 0,
    pg_trgm_weight  INT DEFAULT 0,
    kbdist_weight   INT DEFAULT 0
) RETURNS SETOF search.symspell_lookup_output AS $F$
DECLARE
    prefix_length INT;
    maxED         INT;
    word_list   TEXT[];
    edit_list   TEXT[] := '{}';
    seen_list   TEXT[] := '{}';
    output      search.symspell_lookup_output;
    output_list search.symspell_lookup_output[];
    entry       RECORD;
    entry_key   TEXT;
    prefix_key  TEXT;
    sugg        TEXT;
    input       TEXT;
    word        TEXT;
    w_pos       INT := -1;
    smallest_ed INT := -1;
    global_ed   INT;
BEGIN
    SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
    prefix_length := COALESCE(prefix_length, 6);

    SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
    maxED := COALESCE(maxED, 3);

    word_list := ARRAY_AGG(x) FROM search.symspell_parse_words(raw_input) x;

    -- Common case exact match test for preformance
    IF verbosity = 0 AND CARDINALITY(word_list) = 1 AND CHARACTER_LENGTH(word_list[1]) <= prefix_length THEN
        EXECUTE
          'SELECT  '||search_class||'_suggestions AS suggestions,
                   '||search_class||'_count AS count,
                   prefix_key
             FROM  search.symspell_dictionary
             WHERE prefix_key = $1
                   AND '||search_class||'_count >= $2 
                   AND '||search_class||'_suggestions @> ARRAY[$1]' 
          INTO entry USING evergreen.lowercase(word_list[1]), COALESCE(count_threshold,1);
        IF entry.prefix_key IS NOT NULL THEN
            output.lev_distance := 0; -- definitionally
            output.prefix_key := entry.prefix_key;
            output.prefix_key_count := entry.count;
            output.suggestion_count := entry.count;
            output.input := word_list[1];
            IF xfer_case THEN
                output.suggestion := search.symspell_transfer_casing(output.input, entry.prefix_key);
            ELSE
                output.suggestion := entry.prefix_key;
            END IF;
            output.norm_input := entry.prefix_key;
            output.qwerty_kb_match := 1;
            output.pg_trgm_sim := 1;
            output.soundex_sim := 1;
            RETURN NEXT output;
            RETURN;
        END IF;
    END IF;

    <<word_loop>>
    FOREACH word IN ARRAY word_list LOOP
        w_pos := w_pos + 1;
        input := evergreen.lowercase(word);

        IF CHARACTER_LENGTH(input) > prefix_length THEN
            prefix_key := SUBSTRING(input FROM 1 FOR prefix_length);
            edit_list := ARRAY[input,prefix_key] || search.symspell_generate_edits(prefix_key, 1, maxED);
        ELSE
            edit_list := input || search.symspell_generate_edits(input, 1, maxED);
        END IF;

        SELECT ARRAY_AGG(x ORDER BY CHARACTER_LENGTH(x) DESC) INTO edit_list FROM UNNEST(edit_list) x;

        output_list := '{}';
        seen_list := '{}';
        global_ed := NULL;

        <<entry_key_loop>>
        FOREACH entry_key IN ARRAY edit_list LOOP
            smallest_ed := -1;
            IF global_ed IS NOT NULL THEN
                smallest_ed := global_ed;
            END IF;
            FOR entry IN EXECUTE
                'SELECT  '||search_class||'_suggestions AS suggestions,
                         '||search_class||'_count AS count,
                         prefix_key
                   FROM  search.symspell_dictionary
                   WHERE prefix_key = $1
                         AND '||search_class||'_suggestions IS NOT NULL' 
                USING entry_key
            LOOP
                FOREACH sugg IN ARRAY entry.suggestions LOOP
                    IF NOT seen_list @> ARRAY[sugg] THEN
                        seen_list := seen_list || sugg;
                        IF input = sugg THEN -- exact match, no need to spend time on a call
                            output.lev_distance := 0;
                            output.suggestion_count = entry.count;
                        ELSIF ABS(CHARACTER_LENGTH(input) - CHARACTER_LENGTH(sugg)) > maxED THEN
                            -- They are definitionally too different to consider, just move on.
                            CONTINUE;
                        ELSE
                            --output.lev_distance := levenshtein_less_equal(
                            output.lev_distance := evergreen.levenshtein_damerau_edistance(
                                input,
                                sugg,
                                maxED
                            );
                            IF output.lev_distance < 0 THEN
                                -- The Perl module returns -1 for "more distant than max".
                                output.lev_distance := maxED + 1;
                                -- This short-circuit's the count test below for speed, bypassing
                                -- a couple useless tests.
                                output.suggestion_count := -1;
                            ELSE
                                EXECUTE 'SELECT '||search_class||'_count FROM search.symspell_dictionary WHERE prefix_key = $1'
                                    INTO output.suggestion_count USING sugg;
                            END IF;
                        END IF;

                        -- The caller passes a minimum suggestion count threshold (or uses
                        -- the default of 0) and if the suggestion has that many or less uses
                        -- then we move on to the next suggestion, since this one is too rare.
                        CONTINUE WHEN output.suggestion_count < COALESCE(count_threshold,1);

                        -- Track the smallest edit distance among suggestions from this prefix key.
                        IF smallest_ed = -1 OR output.lev_distance < smallest_ed THEN
                            smallest_ed := output.lev_distance;
                        END IF;

                        -- Track the smallest edit distance for all prefix keys for this word.
                        IF global_ed IS NULL OR smallest_ed < global_ed THEN
                            global_ed = smallest_ed;
                        END IF;

                        -- Only proceed if the edit distance is <= the max for the dictionary.
                        IF output.lev_distance <= maxED THEN
                            IF output.lev_distance > global_ed AND verbosity <= 1 THEN
                                -- Lev distance is our main similarity measure. While
                                -- trgm or soundex similarity could be the main filter,
                                -- Lev is both language agnostic and faster.
                                --
                                -- Here we will skip suggestions that have a longer edit distance
                                -- than the shortest we've already found. This is simply an
                                -- optimization that allows us to avoid further processing
                                -- of this entry. It would be filtered out later.

                                CONTINUE;
                            END IF;

                            -- If we have an exact match on the suggestion key we can also avoid
                            -- some function calls.
                            IF output.lev_distance = 0 THEN
                                output.qwerty_kb_match := 1;
                                output.pg_trgm_sim := 1;
                                output.soundex_sim := 1;
                            ELSE
                                output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(input, sugg);
                                output.pg_trgm_sim := similarity(input, sugg);
                                output.soundex_sim := difference(input, sugg) / 4.0;
                            END IF;

                            -- Fill in some fields
                            IF xfer_case THEN
                                output.suggestion := search.symspell_transfer_casing(word, sugg);
                            ELSE
                                output.suggestion := sugg;
                            END IF;
                            output.prefix_key := entry.prefix_key;
                            output.prefix_key_count := entry.count;
                            output.input := word;
                            output.norm_input := input;
                            output.word_pos := w_pos;

                            -- We can't "cache" a set of generated records directly, so
                            -- here we build up an array of search.symspell_lookup_output
                            -- records that we can revivicate later as a table using UNNEST().
                            output_list := output_list || output;

                            EXIT entry_key_loop WHEN smallest_ed = 0 AND verbosity = 0; -- exact match early exit
                            CONTINUE entry_key_loop WHEN smallest_ed = 0 AND verbosity = 1; -- exact match early jump to the next key
                        END IF; -- maxED test
                    END IF; -- suggestion not seen test
                END LOOP; -- loop over suggestions
            END LOOP; -- loop over entries
        END LOOP; -- loop over entry_keys

        -- Now we're done examining this word
        IF verbosity = 0 THEN
            -- Return the "best" suggestion from the smallest edit
            -- distance group.  We define best based on the weighting
            -- of the non-lev similarity measures and use the suggestion
            -- use count to break ties.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC
                        LIMIT 1;
        ELSIF verbosity = 1 THEN
            -- Return all suggestions from the smallest
            -- edit distance group.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list) WHERE lev_distance = smallest_ed
                    ORDER BY (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 2 THEN
            -- Return everything we find, along with relevant stats
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 3 THEN
            -- Return everything we find from the two smallest edit distance groups
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 4 THEN
            -- Return everything we find from the two smallest edit distance groups that are NOT 0 distance
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) WHERE lev_distance > 0 ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        END IF;
    END LOOP; -- loop over words
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_build_raw_entry (
    raw_input       TEXT,
    source_class    TEXT,
    no_limit        BOOL DEFAULT FALSE,
    prefix_length   INT DEFAULT 6,
    maxED           INT DEFAULT 3
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    key         TEXT;
    del_key     TEXT;
    key_list    TEXT[];
    entry       search.symspell_dictionary%ROWTYPE;
BEGIN
    key := raw_input;

    IF NOT no_limit AND CHARACTER_LENGTH(raw_input) > prefix_length THEN
        key := SUBSTRING(key FROM 1 FOR prefix_length);
        key_list := ARRAY[raw_input, key];
    ELSE
        key_list := ARRAY[key];
    END IF;

    FOREACH del_key IN ARRAY key_list LOOP
        entry.prefix_key := del_key;

        entry.keyword_count := 0;
        entry.title_count := 0;
        entry.author_count := 0;
        entry.subject_count := 0;
        entry.series_count := 0;
        entry.identifier_count := 0;

        entry.keyword_suggestions := '{}';
        entry.title_suggestions := '{}';
        entry.author_suggestions := '{}';
        entry.subject_suggestions := '{}';
        entry.series_suggestions := '{}';
        entry.identifier_suggestions := '{}';

        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'title' THEN entry.title_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'author' THEN entry.author_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'subject' THEN entry.subject_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'series' THEN entry.series_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'identifier' THEN entry.identifier_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;

        IF del_key = raw_input THEN
            IF source_class = 'keyword' THEN entry.keyword_count := 1; END IF;
            IF source_class = 'title' THEN entry.title_count := 1; END IF;
            IF source_class = 'author' THEN entry.author_count := 1; END IF;
            IF source_class = 'subject' THEN entry.subject_count := 1; END IF;
            IF source_class = 'series' THEN entry.series_count := 1; END IF;
            IF source_class = 'identifier' THEN entry.identifier_count := 1; END IF;
        END IF;

        RETURN NEXT entry;
    END LOOP;

    FOR del_key IN SELECT x FROM UNNEST(search.symspell_generate_edits(key, 1, maxED)) x LOOP

        entry.keyword_suggestions := '{}';
        entry.title_suggestions := '{}';
        entry.author_suggestions := '{}';
        entry.subject_suggestions := '{}';
        entry.series_suggestions := '{}';
        entry.identifier_suggestions := '{}';

        IF source_class = 'keyword' THEN entry.keyword_count := 0; END IF;
        IF source_class = 'title' THEN entry.title_count := 0; END IF;
        IF source_class = 'author' THEN entry.author_count := 0; END IF;
        IF source_class = 'subject' THEN entry.subject_count := 0; END IF;
        IF source_class = 'series' THEN entry.series_count := 0; END IF;
        IF source_class = 'identifier' THEN entry.identifier_count := 0; END IF;

        entry.prefix_key := del_key;

        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'title' THEN entry.title_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'author' THEN entry.author_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'subject' THEN entry.subject_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'series' THEN entry.series_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'identifier' THEN entry.identifier_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;

        RETURN NEXT entry;
    END LOOP;

END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_build_entries (
    full_input      TEXT,
    source_class    TEXT,
    old_input       TEXT DEFAULT NULL,
    include_phrases BOOL DEFAULT FALSE
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    prefix_length   INT;
    maxED           INT;
    word_list   TEXT[];
    input       TEXT;
    word        TEXT;
    entry       search.symspell_dictionary;
BEGIN
    IF full_input IS NOT NULL THEN
        SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
        prefix_length := COALESCE(prefix_length, 6);

        SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
        maxED := COALESCE(maxED, 3);

        input := evergreen.lowercase(full_input);
        word_list := ARRAY_AGG(x) FROM search.symspell_parse_words_distinct(input) x;
    
        IF CARDINALITY(word_list) > 1 AND include_phrases THEN
            RETURN QUERY SELECT * FROM search.symspell_build_raw_entry(input, source_class, TRUE, prefix_length, maxED);
        END IF;

        FOREACH word IN ARRAY word_list LOOP
            RETURN QUERY SELECT * FROM search.symspell_build_raw_entry(word, source_class, FALSE, prefix_length, maxED);
        END LOOP;
    END IF;

    IF old_input IS NOT NULL THEN
        input := evergreen.lowercase(old_input);

        FOR word IN SELECT x FROM search.symspell_parse_words_distinct(input) x LOOP
            entry.prefix_key := word;

            entry.keyword_count := 0;
            entry.title_count := 0;
            entry.author_count := 0;
            entry.subject_count := 0;
            entry.series_count := 0;
            entry.identifier_count := 0;

            entry.keyword_suggestions := '{}';
            entry.title_suggestions := '{}';
            entry.author_suggestions := '{}';
            entry.subject_suggestions := '{}';
            entry.series_suggestions := '{}';
            entry.identifier_suggestions := '{}';

            IF source_class = 'keyword' THEN entry.keyword_count := -1; END IF;
            IF source_class = 'title' THEN entry.title_count := -1; END IF;
            IF source_class = 'author' THEN entry.author_count := -1; END IF;
            IF source_class = 'subject' THEN entry.subject_count := -1; END IF;
            IF source_class = 'series' THEN entry.series_count := -1; END IF;
            IF source_class = 'identifier' THEN entry.identifier_count := -1; END IF;

            RETURN NEXT entry;
        END LOOP;
    END IF;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_build_and_merge_entries (
    full_input      TEXT,
    source_class    TEXT,
    old_input       TEXT DEFAULT NULL,
    include_phrases BOOL DEFAULT FALSE
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    new_entry       RECORD;
    conflict_entry  RECORD;
BEGIN

    IF full_input = old_input THEN -- neither NULL, and are the same
        RETURN;
    END IF;

    FOR new_entry IN EXECUTE $q$
        SELECT  count,
                prefix_key,
                evergreen.text_array_merge_unique(s,'{}') suggestions
          FROM  (SELECT prefix_key,
                        ARRAY_AGG($q$ || source_class || $q$_suggestions[1]) s,
                        SUM($q$ || source_class || $q$_count) count
                  FROM  search.symspell_build_entries($1, $2, $3, $4)
                  GROUP BY 1) x
        $q$ USING full_input, source_class, old_input, include_phrases
    LOOP
        EXECUTE $q$
            SELECT  prefix_key,
                    $q$ || source_class || $q$_suggestions suggestions,
                    $q$ || source_class || $q$_count count
              FROM  search.symspell_dictionary
              WHERE prefix_key = $1 $q$
            INTO conflict_entry
            USING new_entry.prefix_key;

        IF new_entry.count <> 0 THEN -- Real word, and count changed
            IF conflict_entry.prefix_key IS NOT NULL THEN -- we'll be updating
                IF conflict_entry.count > 0 THEN -- it's a real word
                    RETURN QUERY EXECUTE $q$
                        UPDATE  search.symspell_dictionary
                           SET  $q$ || source_class || $q$_count = $2
                          WHERE prefix_key = $1
                          RETURNING * $q$
                        USING new_entry.prefix_key, GREATEST(0, new_entry.count + conflict_entry.count);
                ELSE -- it was a prefix key or delete-emptied word before
                    IF conflict_entry.suggestions @> new_entry.suggestions THEN -- already have all suggestions here...
                        RETURN QUERY EXECUTE $q$
                            UPDATE  search.symspell_dictionary
                               SET  $q$ || source_class || $q$_count = $2
                              WHERE prefix_key = $1
                              RETURNING * $q$
                            USING new_entry.prefix_key, GREATEST(0, new_entry.count);
                    ELSE -- new suggestion!
                        RETURN QUERY EXECUTE $q$
                            UPDATE  search.symspell_dictionary
                               SET  $q$ || source_class || $q$_count = $2,
                                    $q$ || source_class || $q$_suggestions = $3
                              WHERE prefix_key = $1
                              RETURNING * $q$
                            USING new_entry.prefix_key, GREATEST(0, new_entry.count), evergreen.text_array_merge_unique(conflict_entry.suggestions,new_entry.suggestions);
                    END IF;
                END IF;
            ELSE
                -- We keep the on-conflict clause just in case...
                RETURN QUERY EXECUTE $q$
                    INSERT INTO search.symspell_dictionary AS d (
                        $q$ || source_class || $q$_count,
                        prefix_key,
                        $q$ || source_class || $q$_suggestions
                    ) VALUES ( $1, $2, $3 ) ON CONFLICT (prefix_key) DO
                        UPDATE SET  $q$ || source_class || $q$_count = d.$q$ || source_class || $q$_count + EXCLUDED.$q$ || source_class || $q$_count,
                                    $q$ || source_class || $q$_suggestions = evergreen.text_array_merge_unique(d.$q$ || source_class || $q$_suggestions, EXCLUDED.$q$ || source_class || $q$_suggestions)
                        RETURNING * $q$
                    USING new_entry.count, new_entry.prefix_key, new_entry.suggestions;
            END IF;
        ELSE -- key only, or no change
            IF conflict_entry.prefix_key IS NOT NULL THEN -- we'll be updating
                IF NOT conflict_entry.suggestions @> new_entry.suggestions THEN -- There are new suggestions
                    RETURN QUERY EXECUTE $q$
                        UPDATE  search.symspell_dictionary
                           SET  $q$ || source_class || $q$_suggestions = $2
                          WHERE prefix_key = $1
                          RETURNING * $q$
                        USING new_entry.prefix_key, evergreen.text_array_merge_unique(conflict_entry.suggestions,new_entry.suggestions);
                END IF;
            ELSE
                RETURN QUERY EXECUTE $q$
                    INSERT INTO search.symspell_dictionary AS d (
                        $q$ || source_class || $q$_count,
                        prefix_key,
                        $q$ || source_class || $q$_suggestions
                    ) VALUES ( $1, $2, $3 ) ON CONFLICT (prefix_key) DO -- key exists, suggestions may be added due to this entry
                        UPDATE SET  $q$ || source_class || $q$_suggestions = evergreen.text_array_merge_unique(d.$q$ || source_class || $q$_suggestions, EXCLUDED.$q$ || source_class || $q$_suggestions)
                    RETURNING * $q$
                    USING new_entry.count, new_entry.prefix_key, new_entry.suggestions;
            END IF;
        END IF;
    END LOOP;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_maintain_entries () RETURNS TRIGGER AS $f$
DECLARE
    search_class    TEXT;
    new_value       TEXT := NULL;
    old_value       TEXT := NULL;
BEGIN
    search_class := COALESCE(TG_ARGV[0], SPLIT_PART(TG_TABLE_NAME,'_',1));

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        new_value := NEW.value;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        old_value := OLD.value;
    END IF;

    PERFORM * FROM search.symspell_build_and_merge_entries(new_value, search_class, old_value);

    RETURN NULL; -- always fired AFTER
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.title_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.author_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.subject_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.series_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.keyword_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.identifier_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

COMMIT;

/* This will generate the queries needed to generate the /file/ that can
 * be used to populate the dictionary table.

select $z$select $y$select $y$||x.id||$y$, '$z$||x.x||$z$', count(*) from search.symspell_build_and_merge_entries($x$$y$ || x.value||$y$$x$, '$z$||x||$z$');$y$ from metabib.$z$||x||$z$_field_entry x;$z$ from (select 'keyword'::text x union select 'title' union select 'author' union select 'subject' union select 'series' union select 'identifier') x;

*/

\qecho ''
\qecho 'The following should be run at the end of the upgrade before any'
\qecho 'reingest occurs.  Because new triggers are installed already,'
\qecho 'updates to indexed strings will cause zero-count dictionary entries'
\qecho 'to be recorded which will require updating every row again (or'
\qecho 'starting from scratch) so best to do this before other batch'
\qecho 'changes.  A later reingest that does not significantly change'
\qecho 'indexed strings will /not/ cause table bloat here, and will be'
\qecho 'as fast as normal.  A copy of the SQL in a ready-to-use, non-escaped'
\qecho 'form is available inside a comment at the end of this upgrade sub-'
\qecho 'script so you do not need to copy this comment from the psql ouptut.'
\qecho ''
\qecho '\\a'
\qecho '\\t'
\qecho ''
\qecho '\\o title'
\qecho 'select value from metabib.title_field_entry;'
\qecho '\\o author'
\qecho 'select value from metabib.author_field_entry;'
\qecho '\\o subject'
\qecho 'select value from metabib.subject_field_entry;'
\qecho '\\o series'
\qecho 'select value from metabib.series_field_entry;'
\qecho '\\o identifier'
\qecho 'select value from metabib.identifier_field_entry;'
\qecho '\\o keyword'
\qecho 'select value from metabib.keyword_field_entry;'
\qecho ''
\qecho '\\o'
\qecho '\\a'
\qecho '\\t'
\qecho ''
\qecho '// Then, at the command line:'
\qecho ''
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl title > title.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl author > author.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl subject > subject.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl series > series.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl identifier > identifier.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl keyword > keyword.sql'
\qecho ''
\qecho '// And, back in psql'
\qecho ''
\qecho 'ALTER TABLE search.symspell_dictionary SET UNLOGGED;'
\qecho 'TRUNCATE search.symspell_dictionary;'
\qecho ''
\qecho '\\i identifier.sql'
\qecho '\\i author.sql'
\qecho '\\i title.sql'
\qecho '\\i subject.sql'
\qecho '\\i series.sql'
\qecho '\\i keyword.sql'
\qecho ''
\qecho 'CLUSTER search.symspell_dictionary USING symspell_dictionary_pkey;'
\qecho 'REINDEX TABLE search.symspell_dictionary;'
\qecho 'ALTER TABLE search.symspell_dictionary SET LOGGED;'
\qecho 'VACUUM ANALYZE search.symspell_dictionary;'
\qecho ''
\qecho 'DROP TABLE search.symspell_dictionary_partial_title;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_author;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_subject;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_series;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_identifier;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_keyword;'

/* To run by hand:

\a
\t

\o title
select value from metabib.title_field_entry;

\o author
select value from metabib.author_field_entry;

\o subject
select value from metabib.subject_field_entry;

\o series
select value from metabib.series_field_entry;

\o identifier
select value from metabib.identifier_field_entry;

\o keyword
select value from metabib.keyword_field_entry;

\o
\a
\t

// Then, at the command line:

$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl title > title.sql
$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl author > author.sql
$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl subject > subject.sql
$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl series > series.sql
$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl identifier > identifier.sql
$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl keyword > keyword.sql

// To the extent your hardware allows, the above commands can be run in 
// in parallel, in different shells.  Each will use a full CPU, and RAM
// may be a limiting resource, so keep an eye on that with `top`.


// And, back in psql

ALTER TABLE search.symspell_dictionary SET UNLOGGED;
TRUNCATE search.symspell_dictionary;

\i identifier.sql
\i author.sql
\i title.sql
\i subject.sql
\i series.sql
\i keyword.sql

CLUSTER search.symspell_dictionary USING symspell_dictionary_pkey;
REINDEX TABLE search.symspell_dictionary;
ALTER TABLE search.symspell_dictionary SET LOGGED;
VACUUM ANALYZE search.symspell_dictionary;

DROP TABLE search.symspell_dictionary_partial_title;
DROP TABLE search.symspell_dictionary_partial_author;
DROP TABLE search.symspell_dictionary_partial_subject;
DROP TABLE search.symspell_dictionary_partial_series;
DROP TABLE search.symspell_dictionary_partial_identifier;
DROP TABLE search.symspell_dictionary_partial_keyword;

*/

