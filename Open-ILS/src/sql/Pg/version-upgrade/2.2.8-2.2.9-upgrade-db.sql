--Upgrade Script for 2.2.8 to 2.2.9
\set eg_version '''2.2.9'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.9', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0788', :eg_version);

-- New view including 264 as a potential tag for publisher and pubdate
CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT publisher.value), ', ') AS publisher,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$) ), ', ') AS pubdate,
    ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

-- Update reporter.materialized_simple_record with new 264-based values for publisher and pubdate
DELETE FROM reporter.materialized_simple_record WHERE id IN (
    SELECT DISTINCT record FROM metabib.full_rec WHERE tag = '264' AND subfield IN ('b', 'c')
);

INSERT INTO reporter.materialized_simple_record
    SELECT DISTINCT rossr.* FROM reporter.old_super_simple_record rossr INNER JOIN metabib.full_rec mfr ON mfr.record = rossr.id
        WHERE mfr.tag = '264' AND mfr.subfield IN ('b', 'c')
;

COMMIT;
