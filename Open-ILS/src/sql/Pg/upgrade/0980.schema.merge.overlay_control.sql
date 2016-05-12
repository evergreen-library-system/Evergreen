BEGIN;

SELECT evergreen.upgrade_deps_block_check('0980', :eg_version);

ALTER TABLE vandelay.merge_profile ADD COLUMN update_bib_source BOOLEAN NOT NULL DEFAULT false;
UPDATE vandelay.merge_profile SET update_bib_source = true WHERE id=2;

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    editor_string   TEXT;
    editor_id       INT;
    v_marc          TEXT;
    v_bib_source    INT;
    update_fields   TEXT[];
    update_query    TEXT;
    update_bib      BOOL;
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

	  SELECT q.update_bib_source INTO update_bib FROM vandelay.merge_profile q where q.id = merge_profile_id;

          IF update_bib THEN
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
        END IF;

        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of biblio.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

COMMIT;
