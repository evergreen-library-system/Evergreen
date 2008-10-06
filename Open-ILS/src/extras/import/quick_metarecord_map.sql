BEGIN;

INSERT INTO metabib.metarecord (fingerprint,master_record)
	SELECT	fingerprint,id
	  FROM	(SELECT	DISTINCT ON (fingerprint)
	  		fingerprint, id, quality
		  FROM	biblio.record_entry
		  ORDER BY fingerprint, quality desc) AS x
	  WHERE	fingerprint IS NOT NULL
            AND fingerprint NOT IN ( SELECT fingerprint FROM metabib.metarecord);

INSERT INTO metabib.metarecord_source_map (metarecord,source)
	SELECT	m.id, b.id
	  FROM	biblio.record_entry b
	  	JOIN metabib.metarecord m ON (m.fingerprint = b.fingerprint)
	  	LEFT JOIN metabib.metarecord_source_map s ON (b.id = s.source)
      WHERE s.id IS NULL;

COMMIT;

VACUUM FULL ANALYZE VERBOSE metabib.metarecord;
VACUUM FULL ANALYZE VERBOSE metabib.metarecord_source_map;

