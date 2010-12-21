BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0472'); -- dbs

CREATE OR REPLACE FUNCTION authority.merge_records ( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    bib_id        INT := 0;
    bib_rec       biblio.record_entry%ROWTYPE;
    auth_link     authority.bib_linking%ROWTYPE;
    ingest_same   boolean;
BEGIN

    -- Defining our terms:
    -- "target record" = the record that will survive the merge
    -- "source record" = the record that is sacrifing its existence and being
    --   replaced by the target record

    -- 1. Update all bib records with the ID from target_record in their $0
    FOR bib_rec IN SELECT bre.* FROM biblio.record_entry bre
      INNER JOIN authority.bib_linking abl ON abl.bib = bre.id
      WHERE abl.authority = source_record LOOP

        UPDATE biblio.record_entry
          SET marc = REGEXP_REPLACE(marc,
            E'(<subfield\\s+code="0"\\s*>[^<]*?\\))' || source_record || '<',
            E'\\1' || target_record || '<', 'g')
          WHERE id = bib_rec.id;

          moved_objects := moved_objects + 1;
    END LOOP;

    -- 2. Grab the current value of reingest on same MARC flag
    SELECT enabled INTO ingest_same
      FROM config.internal_flag
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 3. Temporarily set reingest on same to TRUE
    UPDATE config.internal_flag
      SET enabled = TRUE
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 4. Make a harmless update to target_record to trigger auto-update
    --    in linked bibliographic records
    UPDATE authority.record_entry
      SET deleted = FALSE
      WHERE id = target_record;

    -- 5. "Delete" source_record
    DELETE FROM authority.record_entry
      WHERE id = source_record;

    -- 6. Set "reingest on same MARC" flag back to initial value
    UPDATE config.internal_flag
      SET enabled = ingest_same
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

COMMIT;
