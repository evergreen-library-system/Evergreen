--Upgrade Script for 2.2.7 to 2.2.8
\set eg_version '''2.2.8'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.8', :eg_version);
-- Evergreen DB patch XXXX.function.axis_authority_tags_refs_aggregate.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0784', :eg_version);

CREATE OR REPLACE FUNCTION authority.axis_authority_tags_refs(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
       SELECT  unnest(ARRAY_CAT(
                 ARRAY[a.field],
                 (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.field)
             )) y
       FROM  authority.browse_axis_authority_field_map a
       WHERE axis = $1) x;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags_refs(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.authority_field],
                    (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.authority_field)
                )) y
      FROM  authority.control_set_bib_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags_refs(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_AGG(y) from (
        SELECT  unnest(ARRAY_CAT(
                    ARRAY[a.id],
                    (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.id)
                )) y
      FROM  authority.control_set_authority_field a
      WHERE a.tag = $1) x
$$ LANGUAGE SQL;



INSERT INTO config.upgrade_log (version) VALUES ('0787');

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT, no_thesaurus BOOL ) RETURNS TEXT AS $func$
DECLARE
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    thes_code       TEXT;
    cset            INT;
    heading_text    TEXT;
    tmp_text        TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT;
BEGIN
    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN ( SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    thes_code := vandelay.marc21_extract_fixed_field(marcxml,'Subj');
    IF thes_code IS NULL THEN
        thes_code := '|';
    ELSIF thes_code = 'z' THEN
        thes_code := COALESCE( oils_xpath_string('//*[@tag="040"]/*[@code="f"][1]', marcxml), '' );
    END IF;

    heading_text := '';
    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset AND main_entry IS NULL LOOP
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        first_sf := TRUE;
        FOR sf IN SELECT * FROM regexp_split_to_table(acsaf.sf_list,'') LOOP
            tmp_text := oils_xpath_string('//*[@tag="'||tag_used||'"]/*[@code="'||sf||'"]', marcxml);

            IF first_sf AND tmp_text IS NOT NULL AND nfi_used IS NOT NULL THEN

                tmp_text := SUBSTRING(
                    tmp_text FROM
                    COALESCE(
                        NULLIF(
                            REGEXP_REPLACE(
                                oils_xpath_string('//*[@tag="'||tag_used||'"]/@ind'||nfi_used, marcxml),
                                $$\D+$$,
                                '',
                                'g'
                            ),
                            ''
                        )::INT,
                        0
                    ) + 1
                );

            END IF;

            first_sf := FALSE;

            IF tmp_text IS NOT NULL AND tmp_text <> '' THEN
                heading_text := heading_text || E'\u2021' || sf || ' ' || tmp_text;
            END IF;
        END LOOP;
        EXIT WHEN heading_text <> '';
    END LOOP;

    IF heading_text <> '' THEN
        IF no_thesaurus IS TRUE THEN
            heading_text := tag_used || ' ' || public.naco_normalize(heading_text);
        ELSE
            heading_text := tag_used || '_' || COALESCE(nfi_used,'-') || '_' || thes_code || ' ' || public.naco_normalize(heading_text);
        END IF;
    ELSE
        heading_text := 'NOHEADING_' || thes_code || ' ' || MD5(marcxml);
    END IF;
        RETURN heading_text;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

COMMIT;
