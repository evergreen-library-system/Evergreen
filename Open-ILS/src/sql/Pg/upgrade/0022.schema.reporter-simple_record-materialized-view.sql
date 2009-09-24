BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0022'); --miker

-- Need to recreate this view with DISTINCT calls to ARRAY_ACCUM, thus avoiding duplicated ISBN and ISSN values
CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
        r.fingerprint,
        r.quality,
        r.tcn_source,
        r.tcn_value,
        title.value AS title,
        FIRST(author.value) AS author,
        publisher.value AS publisher,
        SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
        ARRAY_ACCUM( DISTINCT SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
        ARRAY_ACCUM( DISTINCT SUBSTRING(issn.value FROM $$^\S+$$) ) AS issn
  FROM  biblio.record_entry r
        LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
        LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
        LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
        LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
        LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
        LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,8,9;

COMMIT;

