--Upgrade Script for 3.11.1 to 3.11.2
\set eg_version '''3.11.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1382', :eg_version); -- JBoyer / smorrison

-- Remove previous acpl 1 protection
DROP RULE protect_acl_id_1 ON asset.copy_location;

-- Ensure that the owning_lib is set to CONS (equivalent), *should* be a noop.
UPDATE asset.copy_location SET owning_lib = (SELECT id FROM actor.org_unit_ancestor_at_depth(owning_lib,0)) WHERE id = 1;

CREATE OR REPLACE FUNCTION asset.check_delete_copy_location(acpl_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM TRUE FROM asset.copy WHERE location = acpl_id AND NOT deleted LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Copy location % contains active copies and cannot be deleted', acpl_id;
    END IF;
    
    IF acpl_id = 1 THEN
        RAISE EXCEPTION
            'Copy location 1 cannot be deleted';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION asset.copy_location_validate_edit()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.id = 1 THEN
        IF OLD.owning_lib != NEW.owning_lib OR NEW.deleted THEN
            RAISE EXCEPTION 'Copy location 1 cannot be moved or deleted';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER acpl_validate_edit BEFORE UPDATE ON asset.copy_location FOR EACH ROW EXECUTE PROCEDURE asset.copy_location_validate_edit();



SELECT evergreen.upgrade_deps_block_check('1388', :eg_version);

UPDATE action_trigger.event_definition
SET delay = '-24:01:00'::INTERVAL
WHERE reactor = 'Circ::AutoRenew'
AND delay = '-23 hours'::INTERVAL
AND max_delay = '-1 minute'::INTERVAL;



SELECT evergreen.upgrade_deps_block_check('1391', :eg_version);

DROP FUNCTION IF EXISTS evergreen.find_next_open_time(INT, TIMESTAMPTZ, BOOL, TIME, INT); --Get rid of the last version of this function with different arguments so it doesn't cause conflicts when calling it
CREATE OR REPLACE FUNCTION evergreen.find_next_open_time ( circ_lib INT, initial TIMESTAMPTZ, hourly BOOL DEFAULT FALSE, initial_time TIME DEFAULT NULL, has_hoo BOOL DEFAULT TRUE )
    RETURNS TIMESTAMPTZ AS $$
DECLARE
    day_number      INT;
    plus_days       INT;
    final_time      TEXT;
    time_adjusted   BOOL;
    hoo_open        TIME WITHOUT TIME ZONE;
    hoo_close       TIME WITHOUT TIME ZONE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    breakout        INT := 0;
BEGIN

    IF initial_time IS NULL THEN
        initial_time := initial::TIME;
    END IF;

    final_time := (initial + '1 second'::INTERVAL)::TEXT;
    LOOP
        breakout := breakout + 1;

        time_adjusted := FALSE;

        IF has_hoo THEN -- Don't check hours if they have no hoo. I think the behavior in that case is that we act like they're always open? Better than making things due in 2 years.
                        -- Don't expect anyone to call this with it set to false; it's just for our own recursive use.
            day_number := EXTRACT(ISODOW FROM final_time::TIMESTAMPTZ) - 1; --Get which day of the week  it is from which it started on.
            plus_days := 0;
            has_hoo := FALSE; -- set has_hoo to false to check if any days are open (for the first recursion where it's always true)
            FOR i IN 1..7 LOOP
                EXECUTE 'SELECT dow_' || day_number || '_open, dow_' || day_number || '_close FROM actor.hours_of_operation WHERE id = $1'
                    INTO hoo_open, hoo_close
                    USING circ_lib;

                -- RAISE NOTICE 'initial time: %; dow: %; close: %',initial_time,day_number,hoo_close;

                IF hoo_close = '00:00:00' THEN -- bah ... I guess we'll check the next day
                    day_number := (day_number + 1) % 7;
                    plus_days := plus_days + 1;
                    time_adjusted := TRUE;
                    CONTINUE;
                ELSE
                    has_hoo := TRUE; --We do have hours open sometimes, yay!
                END IF;

                IF hoo_close IS NULL THEN -- no hours of operation ... assume no closing?
                    hoo_close := '23:59:59';
                END IF;

                EXIT;
            END LOOP;

            IF NOT has_hoo THEN -- If always closed then forget the extra days - just determine based on closures.
                plus_days := 0;
            END IF;

            final_time := DATE(final_time::TIMESTAMPTZ + (plus_days || ' days')::INTERVAL)::TEXT;
            IF hoo_close <> '00:00:00' AND hourly THEN -- Not a day-granular circ
                final_time := final_time||' '|| hoo_close;
            ELSE
                final_time := final_time||' 23:59:59';
            END IF;
        END IF;

        --RAISE NOTICE 'final_time: %',final_time;

        -- Loop through other closings
        LOOP 
            SELECT * INTO adjacent FROM actor.org_unit_closed WHERE org_unit = circ_lib AND final_time::TIMESTAMPTZ between close_start AND close_end;
            EXIT WHEN adjacent.id IS NULL;
            time_adjusted := TRUE;
            -- RAISE NOTICE 'recursing for closings with final_time: %',final_time;
            final_time := evergreen.find_next_open_time(circ_lib, adjacent.close_end::TIMESTAMPTZ, hourly, initial_time, has_hoo)::TEXT;
        END LOOP;

        EXIT WHEN breakout > 100;
        EXIT WHEN NOT time_adjusted;

    END LOOP;

    RETURN final_time;
END;
$$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1398', :eg_version);

CREATE OR REPLACE FUNCTION search.symspell_lookup(
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

                SELECT  HSTORE(
                            ARRAY_AGG(
                                ARRAY[s, evergreen.levenshtein_damerau_edistance(input,s,maxED)::TEXT]
                                    ORDER BY evergreen.levenshtein_damerau_edistance(input,s,maxED) ASC
                            )
                        )
                  INTO  good_suggs
                  FROM  UNNEST(entry.suggestions) s
                  WHERE (ABS(CHARACTER_LENGTH(s) - CHARACTER_LENGTH(input)) <= maxEd
                        AND evergreen.levenshtein_damerau_edistance(input,s,maxED) BETWEEN 0 AND maxED)
                        AND NOT seen_list @> ARRAY[s];

                CONTINUE WHEN good_suggs IS NULL;

                FOR sugg, output.suggestion_count IN EXECUTE
                    'SELECT  prefix_key, '||search_class||'_count
                       FROM  search.symspell_dictionary
                       WHERE prefix_key = ANY ($1)
                             AND '||search_class||'_count >= $2'
                    USING AKEYS(good_suggs), c_min_suggestion_use_threshold
                LOOP

                    IF NOT seen_list @> ARRAY[sugg] THEN
                        output.lev_distance := good_suggs->sugg;
                        seen_list := seen_list || sugg;

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

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
