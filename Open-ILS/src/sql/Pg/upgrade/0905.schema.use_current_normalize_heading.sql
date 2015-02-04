-- Evergreen DB patch 0905.schema.use_current_normalize_heading.sql
--
-- LP#1415572: ensure current version of authority.normalize_heading() is in place
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0905', :eg_version);

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT, no_thesaurus BOOL ) RETURNS TEXT AS $func$
DECLARE
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    sf_node         TEXT;
    tag_node        TEXT;
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

        FOR tag_node IN SELECT unnest(oils_xpath('//*[@tag="'||tag_used||'"]',marcxml)) LOOP
            FOR sf_node IN SELECT unnest(oils_xpath('./*[contains("'||acsaf.sf_list||'",@code)]',tag_node)) LOOP

                tmp_text := oils_xpath_string('.', sf_node);
                sf := oils_xpath_string('./@code', sf_node);

                IF first_sf AND tmp_text IS NOT NULL AND nfi_used IS NOT NULL THEN

                    tmp_text := SUBSTRING(
                        tmp_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('./@ind'||nfi_used, tag_node),
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
$func$ LANGUAGE PLPGSQL STABLE STRICT;

-- fix heading and simple_headings columns without
-- causing a full authority reingest
ALTER TABLE authority.record_entry DISABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry DISABLE TRIGGER aaa_auth_ingest_or_delete;
ALTER TABLE authority.record_entry DISABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry DISABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry DISABLE TRIGGER map_thesaurus_to_control_set;

UPDATE authority.record_entry SET id = id WHERE heading LIKE 'NOHEADING%';

COMMIT;

-- These need to happen outside of the transaction to avoid this:
-- ERROR: cannot ALTER TABLE "record_entry" because it has pending trigger
-- events
ALTER TABLE authority.record_entry ENABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry ENABLE TRIGGER aaa_auth_ingest_or_delete;
ALTER TABLE authority.record_entry ENABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry ENABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry ENABLE TRIGGER map_thesaurus_to_control_set;
