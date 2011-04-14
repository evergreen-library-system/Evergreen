BEGIN;

INSERT INTO metabib.metarecord (fingerprint, master_record)
        SELECT  DISTINCT ON (b.fingerprint) b.fingerprint, b.id
          FROM  biblio.record_entry b
          WHERE NOT b.deleted
                AND b.id IN (
                    SELECT r.id 
                    FROM biblio.record_entry r 
                    LEFT JOIN metabib.metarecord_source_map k ON (k.source = r.id) 
                    WHERE k.id IS NULL AND r.fingerprint IS NOT NULL
                )
                AND NOT EXISTS ( SELECT 1 FROM metabib.metarecord WHERE fingerprint = b.fingerprint )
          ORDER BY b.fingerprint, b.quality DESC;
 
INSERT INTO metabib.metarecord_source_map (metarecord, source)
        SELECT  m.id, r.id
          FROM  biblio.record_entry r
                JOIN metabib.metarecord m USING (fingerprint)
          WHERE NOT r.deleted
                AND r.id IN (
                    SELECT b.id 
                    FROM biblio.record_entry b 
                    LEFT JOIN metabib.metarecord_source_map k ON (k.source = b.id) 
                    WHERE k.id IS NULL
                );

COMMIT;

VACUUM ANALYZE VERBOSE metabib.metarecord;
VACUUM ANALYZE VERBOSE metabib.metarecord_source_map;

