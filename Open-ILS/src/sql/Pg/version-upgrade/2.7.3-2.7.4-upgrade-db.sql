--Upgrade Script for 2.7.3 to 2.7.4
\set eg_version '''2.7.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.7.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0908', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    editor_string   TEXT;
    editor_id       INT;
    v_marc          TEXT;
    v_bib_source    INT;
    update_fields   TEXT[];
    update_query    TEXT;
BEGIN

    SELECT  q.marc, q.bib_source INTO v_marc, v_bib_source
      FROM  vandelay.queued_bib_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    IF vandelay.template_overlay_bib_record( v_marc, eg_id, merge_profile_id) THEN
        UPDATE  vandelay.queued_bib_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;

        editor_string := (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

        IF editor_string IS NOT NULL AND editor_string <> '' THEN
            SELECT usr INTO editor_id FROM actor.card WHERE barcode = editor_string;

            IF editor_id IS NULL THEN
                SELECT id INTO editor_id FROM actor.usr WHERE usrname = editor_string;
            END IF;

            IF editor_id IS NOT NULL THEN
                --only update the edit date if we have a valid editor
                update_fields := ARRAY_APPEND(update_fields, 'editor = ' || editor_id || ', edit_date = NOW()');
            END IF;
        END IF;

        IF v_bib_source IS NOT NULL THEN
            update_fields := ARRAY_APPEND(update_fields, 'source = ' || v_bib_source);
        END IF;

        IF ARRAY_LENGTH(update_fields, 1) > 0 THEN
            update_query := 'UPDATE biblio.record_entry SET ' || ARRAY_TO_STRING(update_fields, ',') || ' WHERE id = ' || eg_id || ';';
            --RAISE NOTICE 'query: %', update_query;
            EXECUTE update_query;
        END IF;

        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of biblio.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0913', :eg_version);

--stock evergreen comes with 2 merge profiles; move any custom profiles
UPDATE vandelay.merge_profile SET id = id + 100 WHERE id > 2;

--update the same ids in org unit settings, stored in double quotes
UPDATE actor.org_unit_setting
    SET value = '"' || merge_profile_id+100 || '"'
	FROM (
		SELECT id, (regexp_matches(value, '"(\d+)"'))[1]::int as merge_profile_id FROM actor.org_unit_setting
		WHERE name IN (
			'acq.upload.default.vandelay.low_quality_fall_thru_profile',
			'acq.upload.default.vandelay.merge_profile'
		)
	) as foo
	WHERE actor.org_unit_setting.id = foo.id
	AND foo.merge_profile_id > 2;

--set sequence's next value to 100, or more if necessary
SELECT SETVAL('vandelay.merge_profile_id_seq', GREATEST(100, (SELECT MAX(id) FROM vandelay.merge_profile)));


SELECT evergreen.upgrade_deps_block_check('0914', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;            # Source string
    my $pad = shift;               # string to fill.  Typically '0'. This should be a single character.
    my $len = shift;               # length of resultant padded field
    my $find = $len - 1;

    while ($string =~ /(^|\D)(\d{1,$find})($|\D)/) {
        my $padded = $2;
        $padded = $pad x ($len - length($padded)) . $padded;
        $string = $` . $1 . $padded . $3 . $';
    }

    return $string;
$$ LANGUAGE PLPERLU;

COMMIT;

-- recompute the various normalized label fields that use lpad_number_substrings()
UPDATE biblio.monograph_part SET id = id;
UPDATE asset.call_number_prefix SET id = id;
UPDATE asset.call_number_suffix SET id = id;
