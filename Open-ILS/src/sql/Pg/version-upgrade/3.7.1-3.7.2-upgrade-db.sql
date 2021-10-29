--Upgrade Script for 3.7.1 to 3.7.2
\set eg_version '''3.7.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.7.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1266', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.copies', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.copies',
        'Grid Config: eg.grid.catalog.record.copies',
        'cwst', 'label')
    );


SELECT evergreen.upgrade_deps_block_check('1268', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staff.catalog.results.show_more', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staff.catalog.results.show_more',
        'Show more details in Angular staff catalog',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1269', :eg_version);

WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('VIEW_BOOKING_RESERVATION', 'VIEW_BOOKING_RESERVATION_ATTR_MAP'))

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map
        
        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)
            
        --- Anybody who can view resources should also see reservations
        --- at the same level
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'VIEW_BOOKING_RESOURCE'
        );



SELECT evergreen.upgrade_deps_block_check('1270', :eg_version);

INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'BKS', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'COM', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MAP', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MIX', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'REC', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SCO', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SER', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'VIS', 39, 1, ' ');


INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('srce','Srce','Srce');

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(1750, 'srce', ' ', oils_i18n_gettext('1750', 'National bibliographic agency', 'ccvm', 'value')),
(1751, 'srce', 'c', oils_i18n_gettext('1751', 'Cooperative cataloging program', 'ccvm', 'value')),
(1752, 'srce', 'd', oils_i18n_gettext('1752', 'Other', 'ccvm', 'value'));


SELECT evergreen.upgrade_deps_block_check('1272', :eg_version);

DO $$
BEGIN

  PERFORM FROM config.usr_setting_type WHERE name = 'circ.collections.exempt';

  IF NOT FOUND THEN

    INSERT INTO config.usr_setting_type (
      name,
      opac_visible,
      label,
      description,
      datatype,
      reg_default
    ) VALUES (
      'circ.collections.exempt',
      FALSE,
      oils_i18n_gettext(
        'circ.collections.exempt',
        'Collections: Exempt',
        'cust',
        'label'
      ),
      oils_i18n_gettext(
        'circ.collections.exempt',
        'User is exempt from collections tracking/processing',
        'cust',
        'description'
      ),
      'bool',
      'false'
    );

  END IF;

END
$$;


SELECT evergreen.upgrade_deps_block_check('1273', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
SELECT  'opac.did_you_mean.max_suggestions',
        'opac',
        'Maximum number of spelling suggestions that may be offered',
        'If set to -1, provide "best" suggestion if mispelled; if set higher than 0, the maximum suggestions that can be provided; if set to 0, disable suggestions.',
        'integer'
  WHERE NOT EXISTS (SELECT 1 FROM config.org_unit_setting_type WHERE name = 'opac.did_you_mean.max_suggestions');



SELECT evergreen.upgrade_deps_block_check('1279', :eg_version);

UPDATE config.org_unit_setting_type SET fm_class='cnal', datatype='link' WHERE name='ui.patron.default_inet_access_level';



SELECT evergreen.upgrade_deps_block_check('1282', :eg_version);

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



SELECT evergreen.upgrade_deps_block_check('1283', :eg_version); -- rhamby/ehardy/jboyer

UPDATE asset.call_number SET record = -1 WHERE id = -1 AND record != -1;

CREATE RULE protect_bre_id_neg1 AS ON UPDATE TO biblio.record_entry WHERE OLD.id = -1 DO INSTEAD NOTHING;
CREATE RULE protect_acl_id_1 AS ON UPDATE TO asset.copy_location WHERE OLD.id = 1 DO INSTEAD NOTHING;
CREATE RULE protect_acn_id_neg1 AS ON UPDATE TO asset.call_number WHERE OLD.id = -1 DO INSTEAD NOTHING;

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- we don't merge bib -1 
    IF target_record = -1 OR source_record = -1 THEN 
       RETURN 0;
    END IF;

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
            ' tag="856"' ||
            ' ind1="' || FIRST(ind1) || '"'  ||
            ' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

    -- Find and move metarecords to the target record
    SELECT    INTO metarec *
      FROM    metabib.metarecord
      WHERE    master_record = source_record;

    IF FOUND THEN
        UPDATE    metabib.metarecord
          SET    master_record = target_record,
            mods = NULL
          WHERE    id = metarec.id;

        moved_objects := moved_objects + 1;
    END IF;

    -- Find call numbers attached to the source ...
    FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

        SELECT    INTO target_cn *
          FROM    asset.call_number
          WHERE    label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
            AND owning_lib = source_cn.owning_lib
            AND record = target_record
            AND NOT deleted;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copies to that, and ...
            UPDATE    asset.copy
              SET    call_number = target_cn.id
              WHERE    call_number = source_cn.id;

            -- ... move V holds to the move-target call number
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
        
                UPDATE    action.hold_request
                  SET    target = target_cn.id
                  WHERE    id = hold.id;
        
                moved_objects := moved_objects + 1;
            END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

        -- ... if not ...
        ELSE
            -- ... just move the call number to the target record
            UPDATE    asset.call_number
              SET    record = target_record
              WHERE    id = source_cn.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find T holds targeting the source record ...
    FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

        -- ... and move them to the target record
        UPDATE    action.hold_request
          SET    target = target_record
          WHERE    id = hold.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial records targeting the source record ...
    FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    serial.record_entry
          SET    record = target_record
          WHERE    id = ser_rec.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial subscriptions targeting the source record ...
    FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
        -- ... and move them to the target record
        UPDATE    serial.subscription
          SET    record_entry = target_record
          WHERE    id = ser_sub.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find booking resource types targeting the source record ...
    FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    booking.resource_type
          SET    record = target_record
          WHERE    id = booking.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find acq lineitems targeting the source record ...
    FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
        -- ... and move them to the target record
        UPDATE    acq.lineitem
          SET    eg_bib_id = target_record
          WHERE    id = acq_lineitem.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find acq user purchase requests targeting the source record ...
    FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
        -- ... and move them to the target record
        UPDATE    acq.user_request
          SET    eg_bib = target_record
          WHERE    id = acq_request.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find parts attached to the source ...
    FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

        SELECT    INTO target_part *
          FROM    biblio.monograph_part
          WHERE    label = source_part.label
            AND record = target_record;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copy-part maps to that, and ...
            UPDATE    asset.copy_part_map
              SET    part = target_part.id
              WHERE    part = source_part.id;

            -- ... move P holds to the move-target part
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
        
                UPDATE    action.hold_request
                  SET    target = target_part.id
                  WHERE    id = hold.id;
        
                moved_objects := moved_objects + 1;
            END LOOP;

        -- ... if not ...
        ELSE
            -- ... just move the part to the target record
            UPDATE    biblio.monograph_part
              SET    record = target_record
              WHERE    id = source_part.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find multi_home items attached to the source ...
    FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    biblio.peer_bib_copy_map
          SET    peer_record = target_record
          WHERE    id = multi_home.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- And delete mappings where the item's home bib was merged with the peer bib
    DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
        SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
        FROM asset.copy WHERE id = target_copy
    );

    -- Apply merge tracking
    UPDATE biblio.record_entry 
        SET merge_date = NOW() WHERE id = target_record;

    UPDATE biblio.record_entry
        SET merge_date = NOW(), merged_to = target_record
        WHERE id = source_record;

    -- replace book bag entries of source_record with target_record
    UPDATE container.biblio_record_entry_bucket_item
        SET target_biblio_record_entry = target_record
        WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'bookbag')
        AND target_biblio_record_entry = source_record;

    -- Finally, "delete" the source record
    UPDATE biblio.record_entry SET active = FALSE WHERE id = source_record;
    DELETE FROM biblio.record_entry WHERE id = source_record;

    -- That's all, folks!
    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;




SELECT evergreen.upgrade_deps_block_check('1294', :eg_version); -- mmorgan / tlittle / JBoyer

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.container.carousel_org_unit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.container.carousel_org_unit',
        'Grid Config: eg.grid.admin.local.container.carousel_org_unit',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.container.carousel', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.container.carousel',
        'Grid Config: eg.grid.admin.container.carousel',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.carousel_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.carousel_type',
        'Grid Config: eg.grid.admin.server.config.carousel_type',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1302', :eg_version);

UPDATE config.org_unit_setting_type
    SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.longoverdue';

UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.lost';

UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.claimsreturned';


SELECT evergreen.upgrade_deps_block_check('1303', :eg_version);

DROP INDEX authority.authority_full_rec_value_index;
CREATE INDEX authority_full_rec_value_index ON authority.full_rec (SUBSTRING(value FOR 1024));

DROP INDEX authority.authority_full_rec_value_tpo_index;
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (SUBSTRING(value FOR 1024) text_pattern_ops);


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
