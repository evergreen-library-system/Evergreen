BEGIN;

ALTER TABLE metabib.metarecord_source_map DROP CONSTRAINT metabib_metarecord_source_map_metarecord_fkey;

TRUNCATE metabib.metarecord;
TRUNCATE metabib.metarecord_source_map;

INSERT INTO metabib.metarecord (fingerprint,master_record)
	SELECT	fingerprint,id
	  FROM	(SELECT	DISTINCT ON (fingerprint)
	  		fingerprint, id, quality
		  FROM	biblio.record_entry
		  ORDER BY fingerprint, quality desc) AS x
	  WHERE	fingerprint IS NOT NULL;

INSERT INTO metabib.metarecord_source_map (metarecord,source)
	SELECT	m.id, b.id
	  FROM	biblio.record_entry b
	  	JOIN metabib.metarecord m ON (m.fingerprint = b.fingerprint);

COMMIT;

BEGIN;

ALTER TABLE metabib.metarecord_source_map ADD CONSTRAINT metabib_metarecord_source_map_metarecord_fkey FOREIGN KEY (metarecord) REFERENCES metabib.metarecord (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;

VACUUM FULL ANALYZE VERBOSE metabib.metarecord;
VACUUM FULL ANALYZE VERBOSE metabib.metarecord_source_map;

