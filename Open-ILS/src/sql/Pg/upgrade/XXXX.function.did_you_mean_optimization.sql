BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE OR REPLACE FUNCTION search.symspell_lookup(
        raw_input text,
        search_class text,
        verbosity integer DEFAULT 2,
        xfer_case boolean DEFAULT false,
        count_threshold integer DEFAULT 1,
        soundex_weight integer DEFAULT 0,
        pg_trgm_weight integer DEFAULT 0,
        kbdist_weight integer DEFAULT 0
) RETURNS SETOF search.symspell_lookup_output
 LANGUAGE plpgsql
AS $function$
DECLARE
    prefix_length INT;
    maxED         INT;
    good_suggs  HSTORE;
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
    i_len       INT;
    l_maxED     INT;
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
        i_len := CHARACTER_LENGTH(input);
        l_maxED := maxED;

        IF CHARACTER_LENGTH(input) > prefix_length THEN
            prefix_key := SUBSTRING(input FROM 1 FOR prefix_length);
            edit_list := ARRAY[input,prefix_key] || search.symspell_generate_edits(prefix_key, 1, l_maxED);
        ELSE
            edit_list := input || search.symspell_generate_edits(input, 1, l_maxED);
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

                SELECT  HSTORE(
                            ARRAY_AGG(
                                ARRAY[s, evergreen.levenshtein_damerau_edistance(input,s,l_maxED)::TEXT]
                                    ORDER BY evergreen.levenshtein_damerau_edistance(input,s,l_maxED) DESC
                            )
                        )
                  INTO  good_suggs
                  FROM  UNNEST(entry.suggestions) s
                  WHERE (ABS(CHARACTER_LENGTH(s) - i_len) <= maxEd AND evergreen.levenshtein_damerau_edistance(input,s,l_maxED) BETWEEN 0 AND l_maxED)
                        AND NOT seen_list @> ARRAY[s];

                CONTINUE WHEN good_suggs IS NULL;

                FOR sugg, output.suggestion_count IN EXECUTE
                    'SELECT  prefix_key, '||search_class||'_count
                       FROM  search.symspell_dictionary
                       WHERE prefix_key = ANY ($1)
                             AND '||search_class||'_count >= $2'
                    USING AKEYS(good_suggs), COALESCE(count_threshold,1)
                LOOP

                    output.lev_distance := good_suggs->sugg;
                    seen_list := seen_list || sugg;

                    -- Track the smallest edit distance among suggestions from this prefix key.
                    IF smallest_ed = -1 OR output.lev_distance < smallest_ed THEN
                        smallest_ed := output.lev_distance;
                    END IF;

                    -- Track the smallest edit distance for all prefix keys for this word.
                    IF global_ed IS NULL OR smallest_ed < global_ed THEN
                        global_ed = smallest_ed;
                        -- And if low verbosity, ignore suggs with a larger distance from here on.
                        IF verbosity <= 1 THEN
                            l_maxED := global_ed;
                        END IF;
                    END IF;

                    -- Lev distance is our main similarity measure. While
                    -- trgm or soundex similarity could be the main filter,
                    -- Lev is both language agnostic and faster.
                    --
                    -- Here we will skip suggestions that have a longer edit distance
                    -- than the shortest we've already found. This is simply an
                    -- optimization that allows us to avoid further processing
                    -- of this entry. It would be filtered out later.
                    CONTINUE WHEN output.lev_distance > global_ed AND verbosity <= 1;

                    -- If we have an exact match on the suggestion key we can also avoid
                    -- some function calls.
                    IF output.lev_distance = 0 THEN
                        output.qwerty_kb_match := 1;
                        output.pg_trgm_sim := 1;
                        output.soundex_sim := 1;
                    ELSE
                        IF kbdist_weight THEN
                            output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(input, sugg);
                        ELSE
                            output.qwerty_kb_match := 0;
                        END IF;
                        IF pg_trgm_weight THEN
                            output.pg_trgm_sim := similarity(input, sugg);
                        ELSE
                            output.pg_trgm_sim := 0;
                        END IF;
                        IF soundex_weight THEN
                            output.soundex_sim := difference(input, sugg) / 4.0;
                        ELSE
                            output.soundex_sim := 0;
                        END IF;
                    END IF;

                    -- Fill in some fields
                    IF xfer_case AND input <> word THEN
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
$function$;

COMMIT;

