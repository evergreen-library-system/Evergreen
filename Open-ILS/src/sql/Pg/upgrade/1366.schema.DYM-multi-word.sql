BEGIN;

SELECT evergreen.upgrade_deps_block_check('1366', :eg_version);

ALTER TABLE config.metabib_class
    ADD COLUMN IF NOT EXISTS variant_authority_suggestion   BOOL NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS symspell_transfer_case         BOOL NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS symspell_skip_correct          BOOL NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS symspell_suggestion_verbosity  INT NOT NULL DEFAULT 2,
    ADD COLUMN IF NOT EXISTS max_phrase_edit_distance       INT NOT NULL DEFAULT 2,
    ADD COLUMN IF NOT EXISTS suggestion_word_option_count   INT NOT NULL DEFAULT 5,
    ADD COLUMN IF NOT EXISTS max_suggestions                INT NOT NULL DEFAULT -1,
    ADD COLUMN IF NOT EXISTS low_result_threshold           INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS min_suggestion_use_threshold   INT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS soundex_weight                 INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS pg_trgm_weight                 INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS keyboard_distance_weight       INT NOT NULL DEFAULT 0;


/* -- may not need these 2 functions
CREATE OR REPLACE FUNCTION search.symspell_parse_positive_words ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT  UNNEST
      FROM  (SELECT UNNEST(x), ROW_NUMBER() OVER ()
              FROM  regexp_matches($1, '(?<!-)\+?([[:alnum:]]+''*[[:alnum:]]*)', 'g') x
            ) y
      WHERE UNNEST IS NOT NULL
      ORDER BY row_number
$F$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_parse_positive_phrases ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT  BTRIM(BTRIM(UNNEST),'"')
      FROM  (SELECT UNNEST(x), ROW_NUMBER() OVER ()
              FROM  regexp_matches($1, '(?:^|\s+)(?:(-?"[^"]+")|(-?\+?[[:alnum:]]+''*?[[:alnum:]]*?))', 'g') x
            ) y
      WHERE UNNEST IS NOT NULL AND UNNEST NOT LIKE '-%'
      ORDER BY row_number
$F$ LANGUAGE SQL STRICT IMMUTABLE;
*/

CREATE OR REPLACE FUNCTION search.symspell_parse_words ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT  UNNEST
      FROM  (SELECT UNNEST(x), ROW_NUMBER() OVER ()
              FROM  regexp_matches($1, '(?:^|\s+)((?:-|\+)?[[:alnum:]]+''*[[:alnum:]]*)', 'g') x
            ) y
      WHERE UNNEST IS NOT NULL
      ORDER BY row_number
$F$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.distribute_phrase_sign (input TEXT) RETURNS TEXT AS $f$
DECLARE
    phrase_sign TEXT;
    output      TEXT;
BEGIN
    output := input;

    IF output ~ '^(?:-|\+)' THEN
        phrase_sign := SUBSTRING(input FROM 1 FOR 1);
        output := SUBSTRING(output FROM 2);
    END IF;

    IF output LIKE '"%"' THEN
        IF phrase_sign IS NULL THEN
            phrase_sign := '+';
        END IF;
        output := BTRIM(output,'"');
    END IF;

    IF phrase_sign IS NOT NULL THEN
        RETURN REGEXP_REPLACE(output,'(^|\s+)(?=[[:alnum:]])','\1'||phrase_sign,'g');
    END IF;

    RETURN output;
END;
$f$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.query_parse_phrases ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT  search.distribute_phrase_sign(UNNEST)
      FROM  (SELECT UNNEST(x), ROW_NUMBER() OVER ()
              FROM  regexp_matches($1, '(?:^|\s+)(?:((?:-|\+)?"[^"]+")|((?:-|\+)?[[:alnum:]]+''*[[:alnum:]]*))', 'g') x
            ) y
      WHERE UNNEST IS NOT NULL
      ORDER BY row_number
$F$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE TYPE search.query_parse_position AS (
    word                TEXT,
    word_pos            INT,
    phrase_in_input_pos INT,
    word_in_phrase_pos  INT,
    negated             BOOL,
    exact               BOOL
);

CREATE OR REPLACE FUNCTION search.query_parse_positions ( raw_input TEXT )
RETURNS SETOF search.query_parse_position AS $F$
DECLARE
    curr_phrase TEXT;
    curr_word   TEXT;
    phrase_pos  INT := 0;
    word_pos    INT := 0;
    pos         INT := 0;
    neg         BOOL;
    ex          BOOL;
BEGIN
    FOR curr_phrase IN SELECT x FROM search.query_parse_phrases(raw_input) x LOOP
        word_pos := 0;
        FOR curr_word IN SELECT x FROM search.symspell_parse_words(curr_phrase) x LOOP
            neg := FALSE;
            ex := FALSE;
            IF curr_word ~ '^(?:-|\+)' THEN
                ex := TRUE;
                IF curr_word LIKE '-%' THEN
                    neg := TRUE;
                END IF;
                curr_word := SUBSTRING(curr_word FROM 2);
            END IF;
            RETURN QUERY SELECT curr_word, pos, phrase_pos, word_pos, neg, ex;
            word_pos := word_pos + 1;
            pos := pos + 1;
        END LOOP;
        phrase_pos := phrase_pos + 1;
    END LOOP;
    RETURN;
END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

/*
select  suggestion as sugg,
        suggestion_count as scount,
        input,
        norm_input,
        prefix_key_count as ncount,
        lev_distance,
        soundex_sim,
        pg_trgm_sim,
        qwerty_kb_match
  from  search.symspell_suggest(
            'Cedenzas (2) for Mosart''s Piano concerto',
            'title',
            '{}',
            2,2,false,5
        )
  where lev_distance is not null
  order by lev_distance,
           suggestion_count desc,
           soundex_sim desc,
           pg_trgm_sim desc,
           qwerty_kb_match desc
;

select * from search.symspell_suggest('piano concerto -jaz','subject','{}',2,2,false,4) order by lev_distance, soundex_sim desc, pg_trgm_sim desc, qwerty_kb_match desc;

*/
CREATE OR REPLACE FUNCTION search.symspell_suggest (
    raw_input       TEXT,
    search_class    TEXT,
    search_fields   TEXT[] DEFAULT '{}',
    max_ed          INT DEFAULT NULL,      -- per word, on average, between norm input and suggestion
    verbosity       INT DEFAULT NULL,      -- 0=Best only; 1=
    skip_correct    BOOL DEFAULT NULL,  -- only suggest replacement words for misspellings?
    max_word_opts   INT DEFAULT NULL,   -- 0 means all combinations, probably want to restrict?
    count_threshold INT DEFAULT NULL    -- min count of records using the terms
) RETURNS SETOF search.symspell_lookup_output AS $F$
DECLARE
    sugg_set         search.symspell_lookup_output[];
    parsed_query_set search.query_parse_position[];
    entry            RECORD;
    auth_entry       RECORD;
    norm_count       RECORD;
    current_sugg     RECORD;
    auth_sugg        RECORD;
    norm_test        TEXT;
    norm_input       TEXT;
    norm_sugg        TEXT;
    query_part       TEXT := '';
    output           search.symspell_lookup_output;
    c_skip_correct                  BOOL;
    c_variant_authority_suggestion  BOOL;
    c_symspell_transfer_case        BOOL;
    c_authority_class_restrict      BOOL;
    c_min_suggestion_use_threshold  INT;
    c_soundex_weight                INT;
    c_pg_trgm_weight                INT;
    c_keyboard_distance_weight      INT;
    c_suggestion_word_option_count  INT;
    c_symspell_suggestion_verbosity INT;
    c_max_phrase_edit_distance      INT;
BEGIN

    -- Gather settings
    SELECT  cmc.min_suggestion_use_threshold,
            cmc.soundex_weight,
            cmc.pg_trgm_weight,
            cmc.keyboard_distance_weight,
            cmc.suggestion_word_option_count,
            cmc.symspell_suggestion_verbosity,
            cmc.symspell_skip_correct,
            cmc.symspell_transfer_case,
            cmc.max_phrase_edit_distance,
            cmc.variant_authority_suggestion,
            cmc.restrict
      INTO  c_min_suggestion_use_threshold,
            c_soundex_weight,
            c_pg_trgm_weight,
            c_keyboard_distance_weight,
            c_suggestion_word_option_count,
            c_symspell_suggestion_verbosity,
            c_skip_correct,
            c_symspell_transfer_case,
            c_max_phrase_edit_distance,
            c_variant_authority_suggestion,
            c_authority_class_restrict
      FROM  config.metabib_class cmc
      WHERE cmc.name = search_class;


    -- Set up variables to use at run time based on params and settings
    c_min_suggestion_use_threshold := COALESCE(count_threshold,c_min_suggestion_use_threshold);
    c_max_phrase_edit_distance := COALESCE(max_ed,c_max_phrase_edit_distance);
    c_symspell_suggestion_verbosity := COALESCE(verbosity,c_symspell_suggestion_verbosity);
    c_suggestion_word_option_count := COALESCE(max_word_opts,c_suggestion_word_option_count);
    c_skip_correct := COALESCE(skip_correct,c_skip_correct);

    SELECT  ARRAY_AGG(
                x ORDER BY  x.word_pos,
                            x.lev_distance,
                            (x.soundex_sim * c_soundex_weight)
                                + (x.pg_trgm_sim * c_pg_trgm_weight)
                                + (x.qwerty_kb_match * c_keyboard_distance_weight) DESC,
                            x.suggestion_count DESC
            ) INTO sugg_set
      FROM  search.symspell_lookup(
                raw_input,
                search_class,
                c_symspell_suggestion_verbosity,
                c_symspell_transfer_case,
                c_min_suggestion_use_threshold,
                c_soundex_weight,
                c_pg_trgm_weight,
                c_keyboard_distance_weight
            ) x
      WHERE x.lev_distance <= c_max_phrase_edit_distance;

    SELECT ARRAY_AGG(x) INTO parsed_query_set FROM search.query_parse_positions(raw_input) x;

    IF search_fields IS NOT NULL AND CARDINALITY(search_fields) > 0 THEN
        SELECT STRING_AGG(id::TEXT,',') INTO query_part FROM config.metabib_field WHERE name = ANY (search_fields);
        IF CHARACTER_LENGTH(query_part) > 0 THEN query_part := 'AND field IN ('||query_part||')'; END IF;
    END IF;

    SELECT STRING_AGG(word,' ') INTO norm_input FROM search.query_parse_positions(evergreen.lowercase(raw_input)) WHERE NOT negated;
    EXECUTE 'SELECT  COUNT(DISTINCT source) AS recs
               FROM  metabib.' || search_class || '_field_entry
               WHERE index_vector @@ plainto_tsquery($$simple$$,$1)' || query_part
            INTO norm_count USING norm_input;

    SELECT STRING_AGG(word,' ') INTO norm_test FROM UNNEST(parsed_query_set);
    FOR current_sugg IN
        SELECT  *
          FROM  search.symspell_generate_combined_suggestions(
                    sugg_set,
                    parsed_query_set,
                    c_skip_correct,
                    c_suggestion_word_option_count
                ) x
    LOOP
        EXECUTE 'SELECT  COUNT(DISTINCT source) AS recs
                   FROM  metabib.' || search_class || '_field_entry
                   WHERE index_vector @@ to_tsquery($$simple$$,$1)' || query_part
                INTO entry USING current_sugg.test;
        SELECT STRING_AGG(word,' ') INTO norm_sugg FROM search.query_parse_positions(current_sugg.suggestion);
        IF entry.recs >= c_min_suggestion_use_threshold AND (norm_count.recs = 0 OR norm_sugg <> norm_input) THEN

            output.input := raw_input;
            output.norm_input := norm_input;
            output.suggestion := current_sugg.suggestion;
            output.suggestion_count := entry.recs;
            output.prefix_key := NULL;
            output.prefix_key_count := norm_count.recs;

            output.lev_distance := NULLIF(evergreen.levenshtein_damerau_edistance(norm_test, norm_sugg, c_max_phrase_edit_distance * CARDINALITY(parsed_query_set)), -1);
            output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(norm_test, norm_sugg);
            output.pg_trgm_sim := similarity(norm_input, norm_sugg);
            output.soundex_sim := difference(norm_input, norm_sugg) / 4.0;

            RETURN NEXT output;
        END IF;

        IF c_variant_authority_suggestion THEN
            FOR auth_sugg IN
                SELECT  DISTINCT m.value AS prefix_key,
                        m.sort_value AS suggestion,
                        v.value as raw_input,
                        v.sort_value as norm_input
                  FROM  authority.simple_heading v
                        JOIN authority.control_set_authority_field csaf ON (csaf.id = v.atag)
                        JOIN authority.heading_field f ON (f.id = csaf.heading_field)
                        JOIN authority.simple_heading m ON (m.record = v.record AND csaf.main_entry = m.atag)
                        JOIN authority.control_set_bib_field csbf ON (csbf.authority_field = csaf.main_entry)
                        JOIN authority.control_set_bib_field_metabib_field_map csbfmfm ON (csbf.id = csbfmfm.bib_field)
                        JOIN config.metabib_field cmf ON (
                                csbfmfm.metabib_field = cmf.id
                                AND (c_authority_class_restrict IS FALSE OR cmf.field_class = search_class)
                                AND (search_fields = '{}'::TEXT[] OR cmf.name = ANY (search_fields))
                        )
                  WHERE v.sort_value = norm_sugg
            LOOP
                EXECUTE 'SELECT  COUNT(DISTINCT source) AS recs
                           FROM  metabib.' || search_class || '_field_entry
                           WHERE index_vector @@ plainto_tsquery($$simple$$,$1)' || query_part
                        INTO auth_entry USING auth_sugg.suggestion;
                IF auth_entry.recs >= c_min_suggestion_use_threshold AND (norm_count.recs = 0 OR auth_sugg.suggestion <> norm_input) THEN
                    output.input := auth_sugg.raw_input;
                    output.norm_input := auth_sugg.norm_input;
                    output.suggestion := auth_sugg.suggestion;
                    output.prefix_key := auth_sugg.prefix_key;
                    output.suggestion_count := auth_entry.recs * -1; -- negative value here 

                    output.lev_distance := 0;
                    output.qwerty_kb_match := 0;
                    output.pg_trgm_sim := 0;
                    output.soundex_sim := 0;

                    RETURN NEXT output;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    RETURN;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_generate_combined_suggestions(
    word_data search.symspell_lookup_output[],
    pos_data search.query_parse_position[],
    skip_correct BOOL DEFAULT TRUE,
    max_words INT DEFAULT 0
) RETURNS TABLE (suggestion TEXT, test TEXT) AS $f$
    my $word_data = shift;
    my $pos_data = shift;
    my $skip_correct = shift;
    my $max_per_word = shift;
    return undef unless (@$word_data and @$pos_data);

    my $last_word_pos = $$word_data[-1]{word_pos};
    my $pos_to_word_map = [ map { [] } 0 .. $last_word_pos ];
    my $parsed_query_data = { map { ($$_{word_pos} => $_) } @$pos_data };

    for my $row (@$word_data) {
        my $wp = +$$row{word_pos};
        next if (
            $skip_correct eq 't' and $$row{lev_distance} > 0
            and @{$$pos_to_word_map[$wp]}
            and $$pos_to_word_map[$wp][0]{lev_distance} == 0
        );
        push @{$$pos_to_word_map[$$row{word_pos}]}, $row;
    }

    gen_step($max_per_word, $pos_to_word_map, $parsed_query_data, $last_word_pos);
    return undef;

    # -----------------------------
    sub gen_step {
        my $max_words = shift;
        my $data = shift;
        my $pos_data = shift;
        my $last_pos = shift;
        my $prefix = shift || '';
        my $test_prefix = shift || '';
        my $current_pos = shift || 0;

        my $word_count = 0;
        for my $sugg ( @{$$data[$current_pos]} ) {
            my $was_inside_phrase = 0;
            my $now_inside_phrase = 0;

            my $word = $$sugg{suggestion};
            $word_count++;

            my $prev_phrase = $$pos_data{$current_pos - 1}{phrase_in_input_pos};
            my $curr_phrase = $$pos_data{$current_pos}{phrase_in_input_pos};
            my $next_phrase = $$pos_data{$current_pos + 1}{phrase_in_input_pos};

            $now_inside_phrase++ if (defined($next_phrase) and $curr_phrase == $next_phrase);
            $was_inside_phrase++ if (defined($prev_phrase) and $curr_phrase == $prev_phrase);

            my $string = $prefix;
            $string .= ' ' if $string;

            if (!$was_inside_phrase) { # might be starting a phrase?
                $string .= '-' if ($$pos_data{$current_pos}{negated} eq 't');
                if ($now_inside_phrase) { # we are! add the double-quote
                    $string .= '"';
                }
                $string .= $word;
            } else { # definitely were in a phrase
                $string .= $word;
                if (!$now_inside_phrase) { # we are not any longer, add the double-quote
                    $string .= '"';
                }
            }

            my $test_string = $test_prefix;
            if ($current_pos > 0) { # have something already, need joiner
                $test_string .= $curr_phrase == $prev_phrase ? ' <-> ' : ' & ';
            }
            $test_string .= '!' if ($$pos_data{$current_pos}{negated} eq 't');
            $test_string .= $word;

            if ($current_pos == $last_pos) {
                return_next {suggestion => $string, test => $test_string};
            } else {
                gen_step($max_words, $data, $pos_data, $last_pos, $string, $test_string, $current_pos + 1);
            }
            
            last if ($max_words and $word_count >= $max_words);
        }
    }
$f$ LANGUAGE PLPERLU IMMUTABLE;

-- Changing parameters, so we have to drop the old one first
DROP FUNCTION search.symspell_lookup;
CREATE FUNCTION search.symspell_lookup (
    raw_input       TEXT,
    search_class    TEXT,
    verbosity       INT DEFAULT NULL,
    xfer_case       BOOL DEFAULT NULL,
    count_threshold INT DEFAULT NULL,
    soundex_weight  INT DEFAULT NULL,
    pg_trgm_weight  INT DEFAULT NULL,
    kbdist_weight   INT DEFAULT NULL
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
    c_symspell_suggestion_verbosity INT;
    c_min_suggestion_use_threshold  INT;
    c_soundex_weight                INT;
    c_pg_trgm_weight                INT;
    c_keyboard_distance_weight      INT;
    c_symspell_transfer_case        BOOL;
BEGIN

    SELECT  cmc.min_suggestion_use_threshold,
            cmc.soundex_weight,
            cmc.pg_trgm_weight,
            cmc.keyboard_distance_weight,
            cmc.symspell_transfer_case,
            cmc.symspell_suggestion_verbosity
      INTO  c_min_suggestion_use_threshold,
            c_soundex_weight,
            c_pg_trgm_weight,
            c_keyboard_distance_weight,
            c_symspell_transfer_case,
            c_symspell_suggestion_verbosity
      FROM  config.metabib_class cmc
      WHERE cmc.name = search_class;

    c_min_suggestion_use_threshold := COALESCE(count_threshold,c_min_suggestion_use_threshold);
    c_symspell_transfer_case := COALESCE(xfer_case,c_symspell_transfer_case);
    c_symspell_suggestion_verbosity := COALESCE(verbosity,c_symspell_suggestion_verbosity);
    c_soundex_weight := COALESCE(soundex_weight,c_soundex_weight);
    c_pg_trgm_weight := COALESCE(pg_trgm_weight,c_pg_trgm_weight);
    c_keyboard_distance_weight := COALESCE(kbdist_weight,c_keyboard_distance_weight);

    SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
    prefix_length := COALESCE(prefix_length, 6);

    SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
    maxED := COALESCE(maxED, 3);

    -- XXX This should get some more thought ... maybe search_normalize?
    word_list := ARRAY_AGG(x.word) FROM search.query_parse_positions(raw_input) x;

    -- Common case exact match test for preformance
    IF c_symspell_suggestion_verbosity = 0 AND CARDINALITY(word_list) = 1 AND CHARACTER_LENGTH(word_list[1]) <= prefix_length THEN
        EXECUTE
          'SELECT  '||search_class||'_suggestions AS suggestions,
                   '||search_class||'_count AS count,
                   prefix_key
             FROM  search.symspell_dictionary
             WHERE prefix_key = $1
                   AND '||search_class||'_count >= $2 
                   AND '||search_class||'_suggestions @> ARRAY[$1]' 
          INTO entry USING evergreen.lowercase(word_list[1]), c_min_suggestion_use_threshold;
        IF entry.prefix_key IS NOT NULL THEN
            output.lev_distance := 0; -- definitionally
            output.prefix_key := entry.prefix_key;
            output.prefix_key_count := entry.count;
            output.suggestion_count := entry.count;
            output.input := word_list[1];
            IF c_symspell_transfer_case THEN
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
                        CONTINUE WHEN output.suggestion_count < c_min_suggestion_use_threshold;

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
                            IF output.lev_distance > global_ed AND c_symspell_suggestion_verbosity <= 1 THEN
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
                            IF c_symspell_transfer_case THEN
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

                            EXIT entry_key_loop WHEN smallest_ed = 0 AND c_symspell_suggestion_verbosity = 0; -- exact match early exit
                            CONTINUE entry_key_loop WHEN smallest_ed = 0 AND c_symspell_suggestion_verbosity = 1; -- exact match early jump to the next key
                        END IF; -- maxED test
                    END IF; -- suggestion not seen test
                END LOOP; -- loop over suggestions
            END LOOP; -- loop over entries
        END LOOP; -- loop over entry_keys

        -- Now we're done examining this word
        IF c_symspell_suggestion_verbosity = 0 THEN
            -- Return the "best" suggestion from the smallest edit
            -- distance group.  We define best based on the weighting
            -- of the non-lev similarity measures and use the suggestion
            -- use count to break ties.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC
                        LIMIT 1;
        ELSIF c_symspell_suggestion_verbosity = 1 THEN
            -- Return all suggestions from the smallest
            -- edit distance group.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list) WHERE lev_distance = smallest_ed
                    ORDER BY (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        ELSIF c_symspell_suggestion_verbosity = 2 THEN
            -- Return everything we find, along with relevant stats
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        ELSIF c_symspell_suggestion_verbosity = 3 THEN
            -- Return everything we find from the two smallest edit distance groups
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        ELSIF c_symspell_suggestion_verbosity = 4 THEN
            -- Return everything we find from the two smallest edit distance groups that are NOT 0 distance
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) WHERE lev_distance > 0 ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        END IF;
    END LOOP; -- loop over words
END;
$F$ LANGUAGE PLPGSQL;

COMMIT;

-- Find the "broadest" value in use, and update the defaults for all classes
DO $do$
DECLARE
    val TEXT;
BEGIN
    SELECT  FIRST(s.value ORDER BY t.depth) INTO val
      FROM  actor.org_unit_setting s
            JOIN actor.org_unit u ON (u.id = s.org_unit)
            JOIN actor.org_unit_type t ON (u.ou_type = t.id)
      WHERE s.name = 'opac.did_you_mean.low_result_threshold';

    IF FOUND AND val IS NOT NULL THEN
        UPDATE config.metabib_class SET low_result_threshold = val::INT;
    END IF;

    SELECT  FIRST(s.value ORDER BY t.depth) INTO val
      FROM  actor.org_unit_setting s
            JOIN actor.org_unit u ON (u.id = s.org_unit)
            JOIN actor.org_unit_type t ON (u.ou_type = t.id)
      WHERE s.name = 'opac.did_you_mean.max_suggestions';

    IF FOUND AND val IS NOT NULL THEN
        UPDATE config.metabib_class SET max_suggestions = val::INT;
    END IF;

    SELECT  FIRST(s.value ORDER BY t.depth) INTO val
      FROM  actor.org_unit_setting s
            JOIN actor.org_unit u ON (u.id = s.org_unit)
            JOIN actor.org_unit_type t ON (u.ou_type = t.id)
      WHERE s.name = 'search.symspell.min_suggestion_use_threshold';

    IF FOUND AND val IS NOT NULL THEN
        UPDATE config.metabib_class SET min_suggestion_use_threshold = val::INT;
    END IF;

    SELECT  FIRST(s.value ORDER BY t.depth) INTO val
      FROM  actor.org_unit_setting s
            JOIN actor.org_unit u ON (u.id = s.org_unit)
            JOIN actor.org_unit_type t ON (u.ou_type = t.id)
      WHERE s.name = 'search.symspell.soundex.weight';

    IF FOUND AND val IS NOT NULL THEN
        UPDATE config.metabib_class SET soundex_weight = val::INT;
    END IF;

    SELECT  FIRST(s.value ORDER BY t.depth) INTO val
      FROM  actor.org_unit_setting s
            JOIN actor.org_unit u ON (u.id = s.org_unit)
            JOIN actor.org_unit_type t ON (u.ou_type = t.id)
      WHERE s.name = 'search.symspell.pg_trgm.weight';

    IF FOUND AND val IS NOT NULL THEN
        UPDATE config.metabib_class SET pg_trgm_weight = val::INT;
    END IF;

    SELECT  FIRST(s.value ORDER BY t.depth) INTO val
      FROM  actor.org_unit_setting s
            JOIN actor.org_unit u ON (u.id = s.org_unit)
            JOIN actor.org_unit_type t ON (u.ou_type = t.id)
      WHERE s.name = 'search.symspell.keyboard_distance.weight';

    IF FOUND AND val IS NOT NULL THEN
        UPDATE config.metabib_class SET keyboard_distance_weight = val::INT;
    END IF;
END;
$do$;

