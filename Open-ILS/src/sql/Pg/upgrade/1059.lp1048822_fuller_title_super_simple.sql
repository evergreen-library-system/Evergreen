BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1059', :eg_version); --Stompro/DPearl/kmlussier

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    CONCAT_WS(' ', FIRST(title.value),FIRST(title_np.val)) AS title,
    FIRST(author.value) AS author,
    STRING_AGG(DISTINCT publisher.value, ', ') AS publisher,
    STRING_AGG(DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$), ', ') AS pubdate,
    CASE WHEN ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') )
    END AS isbn,
    CASE WHEN ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') )
    END AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN ( -- Grab 245 N and P subfields in the order that they appear.
      SELECT b.record, string_agg(val, ' ') AS val FROM (
	     SELECT title_np.record, title_np.value AS val
	      FROM metabib.full_rec title_np
	      WHERE
	      title_np.tag = '245'
			AND title_np.subfield IN ('p','n')			
			ORDER BY title_np.id
		) b
		GROUP BY 1
	 ) title_np ON (title_np.record=r.id) 
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

  
  -- Remove trigger on biblio.record_entry
  SELECT reporter.disable_materialized_simple_record_trigger();
  
  -- Rebuild reporter.materialized_simple_record
  SELECT reporter.enable_materialized_simple_record_trigger();
  
  COMMIT;
