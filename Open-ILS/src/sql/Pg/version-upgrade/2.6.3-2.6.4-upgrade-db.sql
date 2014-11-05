--Upgrade Script for 2.6.3 to 2.6.4
\set eg_version '''2.6.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.6.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0892', :eg_version);

CREATE OR REPLACE VIEW metabib.record_attr_flat AS
    SELECT  v.source AS id,
            m.attr AS attr,
            m.value AS value
      FROM  metabib.record_attr_vector_list v
            LEFT JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
        UNION
    SELECT  v.source AS id,
            c.ctype AS attr,
            c.code AS value
      FROM  metabib.record_attr_vector_list v
            LEFT JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) );

CREATE OR REPLACE FUNCTION unapi.mmr_mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mmr/' || $1 AS metarecord
        ),
        (SELECT XMLAGG(foo.y)
          FROM (
            WITH sourcelist AS (
                WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id
                    FROM actor.org_unit WHERE shortname = $5 LIMIT 1)
                SELECT source
                FROM metabib.metarecord_source_map, aou
                WHERE metarecord = $1 AND (
                    EXISTS (
                        SELECT 1 FROM asset.opac_visible_copies
                        WHERE record = source AND circ_lib IN (
                            SELECT id FROM actor.org_unit_descendants(aou.id, $6))
                        LIMIT 1
                    )
                    OR EXISTS (SELECT 1 FROM located_uris(source, aou.id, $10) LIMIT 1)
                )
            )
            SELECT  cmra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            cmra.attr AS name,
                            cmra.value AS "coded-value",
                            cmra.aid AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        cmra.value
                    )
              FROM  (
                SELECT  v.source AS id,
                        c.id AS aid,
                        c.ctype AS attr,
                        c.code AS value
                  FROM  metabib.record_attr_vector_list v
                        JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) )
                ) AS cmra
                    JOIN config.record_attr_definition rad ON (cmra.attr = rad.name)
                    JOIN sourcelist ON (cmra.id = sourcelist.source)
                UNION ALL
            SELECT  umra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            umra.attr AS name,
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        umra.value
                    )
              FROM  (
                SELECT  v.source AS id,
                        m.id AS aid,
                        m.attr AS attr,
                        m.value AS value
                  FROM  metabib.record_attr_vector_list v
                        JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
                ) AS umra
                    JOIN config.record_attr_definition rad ON (umra.attr = rad.name)
                    JOIN sourcelist ON (umra.id = sourcelist.source)
                ORDER BY 1

            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('0893', :eg_version); 

CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT  r.id,
    s.metarecord,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    title.value AS title,
    uniform_title.value AS uniform_title,
    author.value AS author,
    publisher.value AS publisher,
    SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
    series_title.value AS series_title,
    series_statement.value AS series_statement,
    summary.value AS summary,
    ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
    ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM  biblio.record_entry r
    JOIN metabib.metarecord_source_map s ON (s.source = r.id)
    LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
    LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
    LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
    LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;


SELECT evergreen.upgrade_deps_block_check('0894', :eg_version);

CREATE INDEX m_b_voider_idx ON money.billing (voider);


SELECT evergreen.upgrade_deps_block_check('0895', :eg_version);

INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('File', '008', 'COM', 26, 1, 'u');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('File', '006', 'COM', 9, 1, 'u');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Freq', '008', 'SER', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Freq', '006', 'SER', 1, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Regl', '008', 'SER', 19, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Regl', '006', 'SER', 2, 1, ' ');

INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('file','File','File');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('freq','Freq','Freq');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('regl','Regl','Regl');

COMMIT;
