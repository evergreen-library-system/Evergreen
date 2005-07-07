BEGIN;

ALTER TABLE metabib.metarecord_source_map DROP CONSTRAINT metabib_metarecord_source_map_metarecord_fkey;

TRUNCATE metabib.metarecord;
TRUNCATE metabib.metarecord_source_map;

INSERT INTO metabib.metarecord (fingerprint,master_record)
	SELECT	fingerprint,max(id)
	  FROM	biblio.record_entry
	  WHERE	fingerprint IS NOT NULL
	  GROUP BY 1;

INSERT INTO metabib.metarecord_source_map (metarecord,source)
	SELECT	m.id, b.id
	  FROM	biblio.record_entry b
	  	JOIN metabib.metarecord m ON (m.fingerprint = b.fingerprint);

ALTER TABLE metabib.metarecord_source_map ADD CONSTRAINT metabib_metarecord_source_map_metarecord_fkey FOREIGN KEY (metarecord) REFERENCES metabib.metarecord (id);

COMMIT;

VACUUM FULL ANALYZE VERBOSE metabib.metarecord;
VACUUM FULL ANALYZE VERBOSE metabib.metarecord_source_map;

