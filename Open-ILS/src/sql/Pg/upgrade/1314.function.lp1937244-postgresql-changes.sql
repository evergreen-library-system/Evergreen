BEGIN;

SELECT evergreen.upgrade_deps_block_check('1314', :eg_version);

CREATE OR REPLACE FUNCTION authority.generate_overlay_template (source_xml TEXT) RETURNS TEXT AS $f$
DECLARE
    cset                INT;
    main_entry          authority.control_set_authority_field%ROWTYPE;
    bib_field           authority.control_set_bib_field%ROWTYPE;
    auth_id             INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', source_xml)::INT;
    tmp_data            XML;
    replace_data        XML[] DEFAULT '{}'::XML[];
    replace_rules       TEXT[] DEFAULT '{}'::TEXT[];
    auth_field          XML[];
    auth_i1             TEXT;
    auth_i2             TEXT;
BEGIN
    IF auth_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Default to the LoC controll set
    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    -- if none, make a best guess
    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN (
                    SELECT  UNNEST(XPATH('//*[local-name()="datafield" and starts-with(@tag,"1")]/@tag',marc::XML)::TEXT[])
                      FROM  authority.record_entry
                      WHERE id = auth_id
                )
          LIMIT 1;
    END IF;

    -- if STILL none, no-op change
    IF cset IS NULL THEN
        RETURN XMLELEMENT(
            name record,
            XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
            XMLELEMENT( name leader, '00881nam a2200193   4500'),
            XMLELEMENT(
                name datafield,
                XMLATTRIBUTES( '905' AS tag, ' ' AS ind1, ' ' AS ind2),
                XMLELEMENT(
                    name subfield,
                    XMLATTRIBUTES('d' AS code),
                    '901c'
                )
            )
        )::TEXT;
    END IF;

    FOR main_entry IN SELECT * FROM authority.control_set_authority_field acsaf WHERE acsaf.control_set = cset AND acsaf.main_entry IS NULL LOOP
        auth_field := XPATH('//*[local-name()="datafield" and @tag="'||main_entry.tag||'"][1]',source_xml::XML);
        auth_i1 := (XPATH('//*[local-name()="datafield"]/@ind1',auth_field[1]))[1];
        auth_i2 := (XPATH('//*[local-name()="datafield"]/@ind2',auth_field[1]))[1];
        IF ARRAY_LENGTH(auth_field,1) > 0 THEN
            FOR bib_field IN SELECT * FROM authority.control_set_bib_field WHERE authority_field = main_entry.id LOOP
                SELECT XMLELEMENT( -- XMLAGG avoids magical <element> creation, but requires unnest subquery
                    name datafield,
                    XMLATTRIBUTES(bib_field.tag AS tag, auth_i1 AS ind1, auth_i2 AS ind2),
                    XMLAGG(UNNEST)
                ) INTO tmp_data FROM UNNEST(XPATH('//*[local-name()="subfield"]', auth_field[1]));
                replace_data := replace_data || tmp_data;
                replace_rules := replace_rules || ( bib_field.tag || main_entry.sf_list || E'[0~\\)' || auth_id || '$]' );
                tmp_data = NULL;
            END LOOP;
            EXIT;
        END IF;
    END LOOP;

    SELECT XMLAGG(UNNEST) INTO tmp_data FROM UNNEST(replace_data);

    RETURN XMLELEMENT(
        name record,
        XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
        XMLELEMENT( name leader, '00881nam a2200193   4500'),
        tmp_data,
        XMLELEMENT(
            name datafield,
            XMLATTRIBUTES( '905' AS tag, ' ' AS ind1, ' ' AS ind2),
            XMLELEMENT(
                name subfield,
                XMLATTRIBUTES('r' AS code),
                ARRAY_TO_STRING(replace_rules,',')
            )
        )
    )::TEXT;
END;
$f$ STABLE LANGUAGE PLPGSQL;

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
          WHERE tag IN (SELECT UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    heading_text := '';
    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset AND main_entry IS NULL LOOP
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;
        first_sf := TRUE;

        FOR tag_node IN SELECT unnest(oils_xpath('//*[@tag="'||tag_used||'"]',marcxml))
        LOOP
            FOR sf_node IN SELECT unnest(oils_xpath('//*[local-name() = "subfield" and contains("'||acsaf.sf_list||'",@code)]',tag_node))
            LOOP

                tmp_text := oils_xpath_string('.', sf_node);
                sf := oils_xpath_string('//*/@code', sf_node);

                IF first_sf AND tmp_text IS NOT NULL AND nfi_used IS NOT NULL THEN

                    tmp_text := SUBSTRING(
                        tmp_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('//*[local-name() = "datafield"]/@ind'||nfi_used, tag_node),
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
            thes_code := authority.extract_thesaurus(marcxml);
            heading_text := tag_used || '_' || COALESCE(nfi_used,'-') || '_' || thes_code || ' ' || public.naco_normalize(heading_text);
        END IF;
    ELSE
        heading_text := 'NOHEADING_' || thes_code || ' ' || MD5(marcxml);
    END IF;

    RETURN heading_text;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

CREATE OR REPLACE FUNCTION vandelay.ingest_items ( import_id BIGINT, attr_def_id BIGINT ) RETURNS SETOF vandelay.import_item AS $$
DECLARE

    owning_lib      TEXT;
    circ_lib        TEXT;
    call_number     TEXT;
    copy_number     TEXT;
    status          TEXT;
    location        TEXT;
    circulate       TEXT;
    deposit         TEXT;
    deposit_amount  TEXT;
    ref             TEXT;
    holdable        TEXT;
    price           TEXT;
    barcode         TEXT;
    circ_modifier   TEXT;
    circ_as_type    TEXT;
    alert_message   TEXT;
    opac_visible    TEXT;
    pub_note        TEXT;
    priv_note       TEXT;
    internal_id     TEXT;
    stat_cat_data   TEXT;
    parts_data      TEXT;

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpaths          TEXT[];
    tmp_str         TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id;

        -- Build the combined XPath

        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*' || attr_def.owning_lib
            END;

        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*' || attr_def.circ_lib
            END;

        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@code="' || attr_def.call_number || '"]'
                ELSE '//*' || attr_def.call_number
            END;

        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*' || attr_def.copy_number
            END;

        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@code="' || attr_def.status || '"]'
                ELSE '//*' || attr_def.status
            END;

        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@code="' || attr_def.location || '"]'
                ELSE '//*' || attr_def.location
            END;

        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@code="' || attr_def.circulate || '"]'
                ELSE '//*' || attr_def.circulate
            END;

        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@code="' || attr_def.deposit || '"]'
                ELSE '//*' || attr_def.deposit
            END;

        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*' || attr_def.deposit_amount
            END;

        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@code="' || attr_def.ref || '"]'
                ELSE '//*' || attr_def.ref
            END;

        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@code="' || attr_def.holdable || '"]'
                ELSE '//*' || attr_def.holdable
            END;

        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@code="' || attr_def.price || '"]'
                ELSE '//*' || attr_def.price
            END;

        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@code="' || attr_def.barcode || '"]'
                ELSE '//*' || attr_def.barcode
            END;

        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*' || attr_def.circ_modifier
            END;

        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*' || attr_def.circ_as_type
            END;

        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*' || attr_def.alert_message
            END;

        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*' || attr_def.priv_note
            END;

        internal_id :=
            CASE
                WHEN attr_def.internal_id IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.internal_id ) = 1 THEN '//*[@code="' || attr_def.internal_id || '"]'
                ELSE '//*' || attr_def.internal_id
            END;

        stat_cat_data :=
            CASE
                WHEN attr_def.stat_cat_data IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.stat_cat_data ) = 1 THEN '//*[@code="' || attr_def.stat_cat_data || '"]'
                ELSE '//*' || attr_def.stat_cat_data
            END;

        parts_data :=
            CASE
                WHEN attr_def.parts_data IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.parts_data ) = 1 THEN '//*[@code="' || attr_def.parts_data || '"]'
                ELSE '//*' || attr_def.parts_data
            END;



        xpaths := ARRAY[owning_lib, circ_lib, call_number, copy_number, status, location, circulate,
                        deposit, deposit_amount, ref, holdable, price, barcode, circ_modifier, circ_as_type,
                        alert_message, pub_note, priv_note, internal_id, stat_cat_data, parts_data, opac_visible];

        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_tag_to_table( (SELECT marc FROM vandelay.queued_bib_record WHERE id = import_id), attr_def.tag, xpaths)
                            AS t( ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, internal_id TEXT,
                                  stat_cat_data TEXT, parts_data TEXT, opac_vis TEXT )
        LOOP

            attr_set.import_error := NULL;
            attr_set.error_detail := NULL;
            attr_set.deposit_amount := NULL;
            attr_set.copy_number := NULL;
            attr_set.price := NULL;
            attr_set.circ_modifier := NULL;
            attr_set.location := NULL;
            attr_set.barcode := NULL;
            attr_set.call_number := NULL;

            IF tmp_attr_set.pr != '' THEN
                tmp_str = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
                IF tmp_str = '' THEN
                    attr_set.import_error := 'import.item.invalid.price';
                    attr_set.error_detail := tmp_attr_set.pr; -- original value
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
                attr_set.price := tmp_str::NUMERIC(8,2);
            END IF;

            IF tmp_attr_set.dep_amount != '' THEN
                tmp_str = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');
                IF tmp_str = '' THEN
                    attr_set.import_error := 'import.item.invalid.deposit_amount';
                    attr_set.error_detail := tmp_attr_set.dep_amount;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
                attr_set.deposit_amount := tmp_str::NUMERIC(8,2);
            END IF;

            IF tmp_attr_set.cnum != '' THEN
                tmp_str = REGEXP_REPLACE(tmp_attr_set.cnum, E'[^0-9]', '', 'g');
                IF tmp_str = '' THEN
                    attr_set.import_error := 'import.item.invalid.copy_number';
                    attr_set.error_detail := tmp_attr_set.cnum;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
                attr_set.copy_number := tmp_str::INT;
            END IF;

            IF tmp_attr_set.ol != '' THEN
                SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.owning_lib';
                    attr_set.error_detail := tmp_attr_set.ol;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            IF tmp_attr_set.clib != '' THEN
                SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_lib';
                    attr_set.error_detail := tmp_attr_set.clib;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            IF tmp_attr_set.cs != '' THEN
                SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.status';
                    attr_set.error_detail := tmp_attr_set.cs;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            IF COALESCE(tmp_attr_set.circ_mod, '') = '' THEN

                -- no circ mod defined, see if we should apply a default
                SELECT INTO attr_set.circ_modifier TRIM(BOTH '"' FROM value)
                    FROM actor.org_unit_ancestor_setting(
                        'vandelay.item.circ_modifier.default',
                        attr_set.owning_lib
                    );

                -- make sure the value from the org setting is still valid
                PERFORM 1 FROM config.circ_modifier WHERE code = attr_set.circ_modifier;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_modifier';
                    attr_set.error_detail := tmp_attr_set.circ_mod;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;

            ELSE

                SELECT code INTO attr_set.circ_modifier FROM config.circ_modifier WHERE code = tmp_attr_set.circ_mod;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_modifier';
                    attr_set.error_detail := tmp_attr_set.circ_mod;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            IF tmp_attr_set.circ_as != '' THEN
                SELECT code INTO attr_set.circ_as_type FROM config.coded_value_map WHERE ctype = 'item_type' AND code = tmp_attr_set.circ_as;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_as_type';
                    attr_set.error_detail := tmp_attr_set.circ_as;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            IF COALESCE(tmp_attr_set.cl, '') = '' THEN
                -- no location specified, see if we should apply a default

                SELECT INTO attr_set.location TRIM(BOTH '"' FROM value)
                    FROM actor.org_unit_ancestor_setting(
                        'vandelay.item.copy_location.default',
                        attr_set.owning_lib
                    );

                -- make sure the value from the org setting is still valid
                PERFORM 1 FROM asset.copy_location
                    WHERE id = attr_set.location AND NOT deleted;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.location';
                    attr_set.error_detail := tmp_attr_set.cs;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            ELSE

                -- search up the org unit tree for a matching copy location
                WITH RECURSIVE anscestor_depth AS (
                    SELECT  ou.id,
                        out.depth AS depth,
                        ou.parent_ou
                    FROM  actor.org_unit ou
                        JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                    WHERE ou.id = COALESCE(attr_set.owning_lib, attr_set.circ_lib)
                        UNION ALL
                    SELECT  ou.id,
                        out.depth,
                        ou.parent_ou
                    FROM  actor.org_unit ou
                        JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                        JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
                ) SELECT  cpl.id INTO attr_set.location
                    FROM  anscestor_depth a
                        JOIN asset.copy_location cpl ON (cpl.owning_lib = a.id)
                    WHERE LOWER(cpl.name) = LOWER(tmp_attr_set.cl)
                        AND NOT cpl.deleted
                    ORDER BY a.depth DESC
                    LIMIT 1;

                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.location';
                    attr_set.error_detail := tmp_attr_set.cs;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            attr_set.circulate      :=
                LOWER( SUBSTRING( tmp_attr_set.circ, 1, 1)) IN ('t','y','1')
                OR LOWER(tmp_attr_set.circ) = 'circulating'; -- BOOL

            attr_set.deposit        :=
                LOWER( SUBSTRING( tmp_attr_set.dep, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.dep) = 'deposit'; -- BOOL

            attr_set.holdable       :=
                LOWER( SUBSTRING( tmp_attr_set.hold, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.hold) = 'holdable'; -- BOOL

            attr_set.opac_visible   :=
                LOWER( SUBSTRING( tmp_attr_set.opac_vis, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.opac_vis) = 'visible'; -- BOOL

            attr_set.ref            :=
                LOWER( SUBSTRING( tmp_attr_set.r, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.r) = 'reference'; -- BOOL

            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.internal_id    := tmp_attr_set.internal_id::BIGINT;
            attr_set.stat_cat_data  := tmp_attr_set.stat_cat_data; -- TEXT,
            attr_set.parts_data     := tmp_attr_set.parts_data; -- TEXT,

            RETURN NEXT attr_set;

        END LOOP;

    END IF;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_quality ( marc TEXT, best_lang TEXT, best_type TEXT ) RETURNS INT AS $func$
DECLARE
    qual        INT;
    ldr         TEXT;
    tval        TEXT;
    tval_rec    RECORD;
    bval        TEXT;
    bval_rec    RECORD;
    type_map    RECORD;
    ff_pos      RECORD;
    ff_tag_data TEXT;
BEGIN

    IF marc IS NULL OR marc = '' THEN
        RETURN NULL;
    END IF;

    -- First, the count of tags
    qual := ARRAY_UPPER(oils_xpath('//*[local-name()="datafield"]', marc), 1);

    -- now go through a bunch of pain to get the record type
    IF best_type IS NOT NULL THEN
        ldr := (oils_xpath('//*[local-name()="leader"]/text()', marc))[1];

        IF ldr IS NOT NULL THEN
            SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
            SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


            tval := SUBSTRING( ldr, tval_rec.start_pos + 1, tval_rec.length );
            bval := SUBSTRING( ldr, bval_rec.start_pos + 1, bval_rec.length );

            -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr;

            SELECT * INTO type_map FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';

            IF type_map.code IS NOT NULL THEN
                IF best_type = type_map.code THEN
                    qual := qual + qual / 2;
                END IF;

                FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = 'Lang' AND rec_type = type_map.code ORDER BY tag DESC LOOP
                    ff_tag_data := SUBSTRING((oils_xpath('//*[@tag="' || ff_pos.tag || '"]/text()',marc))[1], ff_pos.start_pos + 1, ff_pos.length);
                    IF ff_tag_data = best_lang THEN
                            qual := qual + 100;
                    END IF;
                END LOOP;
            END IF;
        END IF;
    END IF;

    -- Now look for some quality metrics
    -- DCL record?
    IF ARRAY_UPPER(oils_xpath('//*[@tag="040"]/*[@code="a" and contains(.,"DLC")]', marc), 1) = 1 THEN
        qual := qual + 10;
    END IF;

    -- From OCLC?
    IF (oils_xpath('//*[@tag="003"]/text()', marc))[1] ~* E'oclo?c' THEN
        qual := qual + 10;
    END IF;

    RETURN qual;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    heading_row     authority.heading%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    joiner_text     TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
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

    res.record := auth_id;
    res.thesaurus := authority.extract_thesaurus(marcxml);

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP
        res.atag := acsaf.id;

        IF acsaf.heading_field IS NULL THEN
            tag_used := acsaf.tag;
            nfi_used := acsaf.nfi;
            joiner_text := COALESCE(acsaf.joiner, ' ');

            FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)::TEXT[]) LOOP

                heading_text := COALESCE(
                    oils_xpath_string('//*[local-name()="subfield" and contains("'||acsaf.display_sf_list||'",@code)]', tmp_xml, joiner_text),
                    ''
                );

                IF nfi_used IS NOT NULL THEN

                    sort_text := SUBSTRING(
                        heading_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('//*[local-name()="datafield"]/@ind'||nfi_used, tmp_xml::TEXT),
                                    $$\D+$$,
                                    '',
                                    'g'
                                ),
                                ''
                            )::INT,
                            0
                        ) + 1
                    );

                ELSE
                    sort_text := heading_text;
                END IF;

                IF heading_text IS NOT NULL AND heading_text <> '' THEN
                    res.value := heading_text;
                    res.sort_value := public.naco_normalize(sort_text);
                    res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                    RETURN NEXT res;
                END IF;

            END LOOP;
        ELSE
            FOR heading_row IN SELECT * FROM authority.extract_headings(marcxml, ARRAY[acsaf.heading_field]) LOOP
                res.value := heading_row.heading;
                res.sort_value := heading_row.normalized_heading;
                res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                RETURN NEXT res;
            END LOOP;
        END IF;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

CREATE OR REPLACE FUNCTION metabib.remap_metarecord_for_bib(
    bib_id bigint,
    fp text,
    bib_is_deleted boolean DEFAULT false,
    retain_deleted boolean DEFAULT false
) RETURNS bigint AS $function$
DECLARE
    new_mapping     BOOL := TRUE;
    source_count    INT;
    old_mr          BIGINT;
    tmp_mr          metabib.metarecord%ROWTYPE;
    deleted_mrs     BIGINT[];
BEGIN

    -- We need to make sure we're not a deleted master record of an MR
    IF bib_is_deleted THEN
        IF NOT retain_deleted THEN -- Go away for any MR that we're master of, unless retained
            DELETE FROM metabib.metarecord_source_map WHERE source = bib_id;
        END IF;

        FOR old_mr IN SELECT id FROM metabib.metarecord WHERE master_record = bib_id LOOP

            -- Now, are there any more sources on this MR?
            SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = old_mr;

            IF source_count = 0 AND NOT retain_deleted THEN -- No other records
                deleted_mrs := ARRAY_APPEND(deleted_mrs, old_mr); -- Just in case...
                DELETE FROM metabib.metarecord WHERE id = old_mr;

            ELSE -- indeed there are. Update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = (SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC, id ASC LIMIT 1)
                  WHERE id = old_mr;
            END IF;
        END LOOP;

    ELSE -- insert or update

        FOR tmp_mr IN SELECT m.* FROM metabib.metarecord m JOIN metabib.metarecord_source_map s ON (s.metarecord = m.id) WHERE s.source = bib_id LOOP

            -- Find the first fingerprint-matching
            IF old_mr IS NULL AND fp = tmp_mr.fingerprint THEN
                old_mr := tmp_mr.id;
                new_mapping := FALSE;

            ELSE -- Our fingerprint changed ... maybe remove the old MR
                DELETE FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id AND source = bib_id; -- remove the old source mapping
                SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id;
                IF source_count = 0 THEN -- No other records
                    deleted_mrs := ARRAY_APPEND(deleted_mrs, tmp_mr.id);
                    DELETE FROM metabib.metarecord WHERE id = tmp_mr.id;
                END IF;
            END IF;

        END LOOP;

        -- we found no suitable, preexisting MR based on old source maps
        IF old_mr IS NULL THEN
            SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp; -- is there one for our current fingerprint?

            IF old_mr IS NULL THEN -- nope, create one and grab its id
                INSERT INTO metabib.metarecord ( fingerprint, master_record ) VALUES ( fp, bib_id );
                SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp;

            ELSE -- indeed there is. update it with a null cache and recalcualated master record
                UPDATE  metabib.metarecord
                  SET   mods = NULL,
                        master_record = (SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC, id ASC LIMIT 1)
                  WHERE id = old_mr;
            END IF;

        ELSE -- there was one we already attached to, update its mods cache and master_record
            UPDATE  metabib.metarecord
              SET   mods = NULL,
                    master_record = (SELECT id FROM biblio.record_entry WHERE fingerprint = fp AND NOT deleted ORDER BY quality DESC, id ASC LIMIT 1)
              WHERE id = old_mr;
        END IF;

        IF new_mapping THEN
            INSERT INTO metabib.metarecord_source_map (metarecord, source) VALUES (old_mr, bib_id); -- new source mapping
        END IF;

    END IF;

    IF ARRAY_UPPER(deleted_mrs,1) > 0 THEN
        UPDATE action.hold_request SET target = old_mr WHERE target IN ( SELECT unnest(deleted_mrs) ) AND hold_type = 'M'; -- if we had to delete any MRs above, make sure their holds are moved
    END IF;

    RETURN old_mr;

END;
$function$ LANGUAGE plpgsql;

COMMIT;
