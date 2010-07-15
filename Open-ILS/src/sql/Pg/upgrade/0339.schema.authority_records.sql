BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0339'); -- dbs

CREATE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id);

CREATE OR REPLACE FUNCTION authority.merge_records ( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    bib_id        INT := 0;
    bib_rec       biblio.record_entry%ROWTYPE;
    auth_link     authority.bib_linking%ROWTYPE;
BEGIN

    -- 1. Make source_record MARC a copy of the target_record to get auto-sync in linked bib records
    UPDATE authority.record_entry
      SET marc = (
        SELECT marc
          FROM authority.record_entry
          WHERE id = target_record
      )
      WHERE id = source_record;

    -- 2. Update all bib records with the ID from target_record in their $0
    FOR bib_rec IN SELECT bre.* FROM biblio.record_entry bre 
      INNER JOIN authority.bib_linking abl ON abl.bib = bre.id
      WHERE abl.authority = target_record LOOP

        UPDATE biblio.record_entry
          SET marc = REGEXP_REPLACE(marc, 
            E'(<subfield\\s+code="0"\\s*>[^<]*?\\))' || source_record || '<',
            E'\\1' || target_record || '<', 'g')
          WHERE id = bib_rec.id;

          moved_objects := moved_objects + 1;
    END LOOP;

    -- 3. "Delete" source_record
    DELETE FROM authority.record_entry
      WHERE id = source_record;

    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

COMMIT;
