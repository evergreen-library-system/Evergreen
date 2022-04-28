--Upgrade Script for 3.8.0 to 3.9.0
\set eg_version '''3.9.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.9.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1307', :eg_version);

DROP FUNCTION search.query_parser_fts (
    INT,
    INT,
    TEXT,
    INT[],
    INT[],
    INT,
    INT,
    INT,
    BOOL,
    BOOL,
    BOOL,
    INT 
);

DROP TABLE asset.opac_visible_copies;

DROP FUNCTION IF EXISTS asset.refresh_opac_visible_copies_mat_view();

DROP TYPE search.search_result;
DROP TYPE search.search_args;


SELECT evergreen.upgrade_deps_block_check('1308', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.triggers.atevdef', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.triggers.atevdef',
        'Grid Config: eg.grid.admin.local.triggers.atevdef',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.triggers.atenv', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.triggers.atenv',
        'Grid Config: eg.grid.admin.local.triggers.atenv',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.triggers.atevparam', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.triggers.atevparam',
        'Grid Config: eg.grid.admin.local.triggers.atevparam',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1309', :eg_version);

ALTER TABLE asset.course_module_term
        DROP CONSTRAINT course_module_term_name_key;

ALTER TABLE asset.course_module_term
        ADD CONSTRAINT cmt_once_per_owning_lib UNIQUE (owning_lib, name);


SELECT evergreen.upgrade_deps_block_check('1311', :eg_version);

CREATE OR REPLACE FUNCTION biblio.extract_located_uris( bib_id BIGINT, marcxml TEXT, editor_id INT ) RETURNS VOID AS $func$
DECLARE
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner_list  TEXT[];
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;
    current_uri     INT;
    current_map     INT;
    uri_map_count   INT;
    current_uri_map_list    INT[];
    current_map_owner_list  INT[];

BEGIN

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()',uri_xml))[1];
            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];

            IF uri_label IS NULL THEN
                uri_label := uri_href;
            END IF;
            CONTINUE WHEN uri_href IS NULL;

            -- Get the distinct list of libraries wanting to use 
            SELECT  ARRAY_AGG(
                        DISTINCT REGEXP_REPLACE(
                            x,
                            $re$^.*?\((\w+)\).*$$re$,
                            E'\\1'
                        )
                    ) INTO uri_owner_list
              FROM  UNNEST(
                        oils_xpath(
                            '//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',
                            uri_xml
                        )
                    )x;

            IF ARRAY_UPPER(uri_owner_list,1) > 0 THEN

                -- look for a matching uri
                IF uri_use IS NULL THEN
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active;
                    END IF;
                ELSE
                    SELECT id INTO uri_id
                        FROM asset.uri
                        WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active
                        ORDER BY id LIMIT 1;
                    IF NOT FOUND THEN -- create one
                        INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                        SELECT id INTO uri_id
                            FROM asset.uri
                            WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                    END IF;
                END IF;

                FOR j IN 1 .. ARRAY_UPPER(uri_owner_list, 1) LOOP
                    uri_owner := uri_owner_list[j];

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = BTRIM(REPLACE(uri_owner,chr(160),''));
                    CONTINUE WHEN NOT FOUND;

                    -- we need a call number to link through
                    SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    IF NOT FOUND THEN
                        INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                            VALUES (uri_owner_id, bib_id, 'now', 'now', editor_id, editor_id, '##URI##');
                        SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
                    END IF;

                    -- now, link them if they're not already
                    SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    IF NOT FOUND THEN
                        INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
                        SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
                    END IF;

                    current_uri_map_list := current_uri_map_list || uri_map_id;
                    current_map_owner_list := current_map_owner_list || uri_cn_id;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    -- Clear any orphaned URIs, URI mappings and call
    -- numbers for this bib that weren't mapped above.
    FOR current_map IN
        SELECT  m.id
          FROM  asset.uri_call_number_map m
                LEFT JOIN asset.call_number cn ON (cn.id = m.call_number)
          WHERE cn.record = bib_id
                AND cn.label = '##URI##'
                AND (NOT (m.id = ANY (current_uri_map_list))
                     OR current_uri_map_list is NULL)
    LOOP
        SELECT uri INTO current_uri FROM asset.uri_call_number_map WHERE id = current_map;
        DELETE FROM asset.uri_call_number_map WHERE id = current_map;

        SELECT COUNT(*) INTO uri_map_count FROM asset.uri_call_number_map WHERE uri = current_uri;
        IF uri_map_count = 0 THEN
            DELETE FROM asset.uri WHERE id = current_uri;
        END IF;
    END LOOP;

    UPDATE asset.call_number
    SET deleted = TRUE, edit_date = now(), editor = editor_id
    WHERE id IN (
        SELECT  id
          FROM  asset.call_number
          WHERE record = bib_id
                AND label = '##URI##'
                AND NOT deleted
                AND (NOT (id = ANY (current_map_owner_list))
                     OR current_map_owner_list is NULL)
    );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- Remove existing orphaned URIs from the database.
DELETE FROM asset.uri
WHERE id IN
(
SELECT uri.id
FROM asset.uri
LEFT JOIN asset.uri_call_number_map
ON uri_call_number_map.uri = uri.id
LEFT JOIN serial.item
ON item.uri = uri.id
WHERE uri_call_number_map IS NULL
AND item IS NULL
);



SELECT evergreen.upgrade_deps_block_check('1312', :eg_version);

CREATE INDEX aum_editor ON actor.usr_message (editor);


SELECT evergreen.upgrade_deps_block_check('1313', :eg_version); -- alynn26

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.bucket.batch_hold.view', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.view',
        'Grid Config: eg.grid.cat.bucket.batch_hold.view',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.batch_hold.pending', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.pending',
        'Grid Config: eg.grid.cat.bucket.batch_hold.pending',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.batch_hold.events', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.events',
        'Grid Config: eg.grid.cat.bucket.batch_hold.events',
        'cwst', 'label'
    )
), (
    'eg.grid.cat.bucket.batch_hold.list', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.list',
        'Grid Config: eg.grid.cat.bucket.batch_hold.list',
        'cwst', 'label'
    )
);


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


SELECT evergreen.upgrade_deps_block_check('1315', :eg_version);

CREATE TABLE config.ui_staff_portal_page_entry_type (
    code        TEXT PRIMARY KEY,
    label       TEXT NOT NULL
);

INSERT INTO config.ui_staff_portal_page_entry_type (code, label)
VALUES
    ('link', oils_i18n_gettext('link', 'Link', 'cusppet', 'label')),
    ('menuitem', oils_i18n_gettext('menuitem', 'Menu Item', 'cusppet', 'label')),
    ('text', oils_i18n_gettext('text', 'Text and/or HTML', 'cusppet', 'label')),
    ('header', oils_i18n_gettext('header', 'Header', 'cusppet', 'label')),
    ('catalogsearch', oils_i18n_gettext('catalogsearch', 'Catalog Search Box', 'cusppet', 'label'));


CREATE TABLE config.ui_staff_portal_page_entry (
    id          SERIAL PRIMARY KEY,
    page_col    INTEGER NOT NULL,
    col_pos     INTEGER NOT NULL,
    entry_type  TEXT NOT NULL, -- REFERENCES config.ui_staff_portal_page_entry_type(code)
    label       TEXT,
    image_url   TEXT,
    target_url  TEXT,
    entry_text  TEXT,
    owner       INT NOT NULL -- REFERENCES actor.org_unit (id)
);

ALTER TABLE config.ui_staff_portal_page_entry ADD CONSTRAINT cusppe_entry_type_fkey
    FOREIGN KEY (entry_type) REFERENCES  config.ui_staff_portal_page_entry_type(code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.ui_staff_portal_page_entry ADD CONSTRAINT cusppe_owner_fkey
    FOREIGN KEY (owner) REFERENCES  actor.org_unit(id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


SELECT evergreen.upgrade_deps_block_check('1316', :eg_version);

INSERT INTO config.ui_staff_portal_page_entry
    (id, page_col, col_pos, entry_type, label, image_url, target_url, owner)
VALUES
    ( 1, 1, 0, 'header',        oils_i18n_gettext( 1, 'Circulation and Patrons', 'cusppe', 'label'), NULL, NULL, 1)
,   ( 2, 1, 1, 'menuitem',      oils_i18n_gettext( 2, 'Check Out Items', 'cusppe', 'label'), '/images/portal/forward.png', '/eg/staff/circ/patron/bcsearch', 1)
,   ( 3, 1, 2, 'menuitem',      oils_i18n_gettext( 3, 'Check In Items', 'cusppe', 'label'), '/images/portal/back.png', '/eg/staff/circ/checkin/index', 1)
,   ( 4, 1, 3, 'menuitem',      oils_i18n_gettext( 4, 'Search For Patron By Name', 'cusppe', 'label'), '/images/portal/retreivepatron.png', '/eg/staff/circ/patron/search', 1)
,   ( 5, 2, 0, 'header',        oils_i18n_gettext( 5, 'Item Search and Cataloging', 'cusppe', 'label'), NULL, NULL, 1)
,   ( 6, 2, 1, 'catalogsearch', oils_i18n_gettext( 6, 'Search Catalog', 'cusppe', 'label'), NULL, NULL, 1)
,   ( 7, 2, 2, 'menuitem',      oils_i18n_gettext( 7, 'Record Buckets', 'cusppe', 'label'), '/images/portal/bucket.png', '/eg/staff/cat/bucket/record/', 1)
,   ( 8, 2, 3, 'menuitem',      oils_i18n_gettext( 8, 'Item Buckets', 'cusppe', 'label'), '/images/portal/bucket.png', '/eg/staff/cat/bucket/copy/', 1)
,   ( 9, 3, 0, 'header',        oils_i18n_gettext( 9, 'Administration', 'cusppe', 'label'), NULL, NULL, 1)
,   (10, 3, 1, 'link',          oils_i18n_gettext(10, 'Evergreen Documentation', 'cusppe', 'label'), '/images/portal/helpdesk.png', 'https://docs.evergreen-ils.org', 1)
,   (11, 3, 2, 'menuitem',      oils_i18n_gettext(11, 'Workstation Administration', 'cusppe', 'label'), '/images/portal/helpdesk.png', '/eg/staff/admin/workstation/index', 1)
,   (12, 3, 3, 'menuitem',      oils_i18n_gettext(12, 'Reports', 'cusppe', 'label'), '/images/portal/reports.png', '/eg/staff/reporter/legacy/main', 1)
;

SELECT setval('config.ui_staff_portal_page_entry_id_seq', 100);


INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.ui_staff_portal_page_entry', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.ui_staff_portal_page_entry',
        'Grid Config: admin.config.ui_staff_portal_page_entry',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1317', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 636, 'ADMIN_STAFF_PORTAL_PAGE', oils_i18n_gettext( 636,
   'Update the staff client portal page', 'ppl', 'description' ))
;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1318', :eg_version);

-- 950.data.seed-values.sql

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.cover_upload_compression',
    0,
    TRUE,
    oils_i18n_gettext(
        'opac.cover_upload_compression',
        'Cover image uploads are converted to PNG files with this compression, on a scale of 0 (no compression) to 9 (maximum compression), or -1 for the zlib default.',
        'cgf', 'label'
    )
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'opac.cover_upload_max_file_size',
    oils_i18n_gettext('opac.cover_upload_max_file_size',
        'Maximum file size for uploaded cover image files (at time of upload, prior to rescaling).',
        'coust', 'label'),
    'opac',
    oils_i18n_gettext('opac.cover_upload_max_file_size',
        'The number of bytes to allow for a cover image upload.  If unset, defaults to 10737418240 (roughly 10GB).',
        'coust', 'description'),
    'integer'
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 637, 'UPLOAD_COVER_IMAGE', oils_i18n_gettext(637,
    'Upload local cover images for added content.', 'ppl', 'description'))
;


SELECT evergreen.upgrade_deps_block_check('1319', :eg_version);

DO $SQL$
BEGIN
    
    PERFORM TRUE FROM config.usr_setting_type WHERE name = 'cat.copy.templates';

    IF NOT FOUND THEN -- no matching user setting

        PERFORM TRUE FROM config.workstation_setting_type WHERE name = 'cat.copy.templates';

        IF NOT FOUND THEN
            -- no matching workstation setting
            -- Migrate the existing user setting and its data to the new name.

            UPDATE config.usr_setting_type 
            SET name = 'cat.copy.templates' 
            WHERE name = 'webstaff.cat.copy.templates';

            UPDATE actor.usr_setting
            SET name = 'cat.copy.templates' 
            WHERE name = 'webstaff.cat.copy.templates';

        END IF;
    END IF;

END; 
$SQL$;



SELECT evergreen.upgrade_deps_block_check('1320', :eg_version); -- jboyer /  / 

ALTER TABLE reporter.template_folder ADD COLUMN simple_reporter BOOLEAN DEFAULT FALSE;
ALTER TABLE reporter.report_folder ADD COLUMN simple_reporter BOOLEAN DEFAULT FALSE;
ALTER TABLE reporter.output_folder ADD COLUMN simple_reporter BOOLEAN DEFAULT FALSE;

DROP INDEX reporter.rpt_template_folder_once_idx;
DROP INDEX reporter.rpt_report_folder_once_idx;
DROP INDEX reporter.rpt_output_folder_once_idx;

CREATE UNIQUE INDEX rpt_template_folder_once_idx ON reporter.template_folder (name,owner,simple_reporter) WHERE parent IS NULL;
CREATE UNIQUE INDEX rpt_report_folder_once_idx ON reporter.report_folder (name,owner,simple_reporter) WHERE parent IS NULL;
CREATE UNIQUE INDEX rpt_output_folder_once_idx ON reporter.output_folder (name,owner,simple_reporter) WHERE parent IS NULL;

-- Private "transform" to allow for simple report permissions verification
CREATE OR REPLACE FUNCTION reporter.intersect_user_perm_ou(context_ou BIGINT, staff_id BIGINT, perm_code TEXT)
RETURNS BOOLEAN AS $$
  SELECT CASE WHEN context_ou IN (SELECT * FROM permission.usr_has_perm_at_all(staff_id::INT, perm_code)) THEN TRUE ELSE FALSE END;
$$ LANGUAGE SQL;

-- Hey committer, make sure this id is good to go and also in 950.data.seed-values.sql
INSERT INTO permission.perm_list (id, code, description) VALUES
 ( 638, 'RUN_SIMPLE_REPORTS', oils_i18n_gettext(638,
    'Build and run simple reports', 'ppl', 'description'));


INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.reporter.simple.reports', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.reporter.simple.reports',
        'Grid Config: eg.grid.reporter.simple.reports',
        'cwst', 'label'
    )
), (
    'eg.grid.reporter.simple.outputs', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.reporter.simple.outputs',
        'Grid Config: eg.grid.reporter.simple.outputs',
        'cwst', 'label'
    )
);

-- new view parallel to reporter.currently_running
-- and reporter.overdue_reports
CREATE OR REPLACE VIEW reporter.completed_reports AS
  SELECT s.id AS run,
         r.id AS report,
         t.id AS template,
         t.owner AS template_owner,
         r.owner AS report_owner,
         s.runner AS runner,
         t.folder AS template_folder,
         r.folder AS report_folder,
         s.folder AS output_folder,
         r.name AS report_name,
         t.name AS template_name,
         s.start_time,
         s.run_time,
         s.complete_time,
         s.error_code,
         s.error_text
  FROM reporter.schedule s
    JOIN reporter.report r ON r.id = s.report
    JOIN reporter.template t ON t.id = r.template
  WHERE s.complete_time IS NOT NULL;



SELECT evergreen.upgrade_deps_block_check('1321', :eg_version);

CREATE TABLE asset.copy_inventory (
    id                          SERIAL                      PRIMARY KEY,
    inventory_workstation       INTEGER                     REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
    inventory_date              TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    copy                        BIGINT                      NOT NULL
);
CREATE INDEX copy_inventory_copy_idx ON asset.copy_inventory (copy);
CREATE UNIQUE INDEX asset_copy_inventory_date_once_per_copy ON asset.copy_inventory (inventory_date, copy);

CREATE OR REPLACE FUNCTION evergreen.asset_copy_inventory_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, copy:%s$$, NEW.copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_asset_copy_inventory_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_inventory_copy_inh_fkey();

CREATE OR REPLACE FUNCTION asset.copy_may_float_to_inventory_workstation() RETURNS TRIGGER AS $func$
DECLARE
    copy asset.copy%ROWTYPE;
    workstation actor.workstation%ROWTYPE;
BEGIN
    SELECT * INTO copy FROM asset.copy WHERE id = NEW.copy;
    IF FOUND THEN
        SELECT * INTO workstation FROM actor.workstation WHERE id = NEW.inventory_workstation;
        IF FOUND THEN
           IF copy.floating IS NULL THEN
              IF copy.circ_lib <> workstation.owning_lib THEN
                 RAISE EXCEPTION 'Inventory workstation owning lib (%) does not match copy circ lib (%).',
                       workstation.owning_lib, copy.circ_lib;
              END IF;
           ELSE
              IF NOT evergreen.can_float(copy.floating, copy.circ_lib, workstation.owning_lib) THEN
                 RAISE EXCEPTION 'Copy (%) cannot float to inventory workstation owning lib (%).',
                       copy.id, workstation.owning_lib;
              END IF;
           END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER asset_copy_inventory_allowed_trig
        AFTER UPDATE OR INSERT ON asset.copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE asset.copy_may_float_to_inventory_workstation();

INSERT INTO asset.copy_inventory
(inventory_workstation, inventory_date, copy)
SELECT DISTINCT ON (inventory_date, copy) inventory_workstation, inventory_date, copy
FROM asset.latest_inventory
JOIN asset.copy acp ON acp.id = latest_inventory.copy
JOIN actor.workstation ON workstation.id = latest_inventory.inventory_workstation
WHERE acp.circ_lib = workstation.owning_lib
UNION
SELECT DISTINCT ON (inventory_date, copy) inventory_workstation, inventory_date, copy
FROM asset.latest_inventory
JOIN asset.copy acp ON acp.id = latest_inventory.copy
JOIN actor.workstation ON workstation.id = latest_inventory.inventory_workstation
WHERE acp.circ_lib <> workstation.owning_lib
AND acp.floating IS NOT NULL
AND evergreen.can_float(acp.floating, acp.circ_lib, workstation.owning_lib)
ORDER by inventory_date;

DROP TABLE asset.latest_inventory;

CREATE VIEW asset.latest_inventory (id, inventory_workstation, inventory_date, copy) AS
SELECT DISTINCT ON (copy) id, inventory_workstation, inventory_date, copy
FROM asset.copy_inventory
ORDER BY copy, inventory_date DESC;

DROP FUNCTION evergreen.asset_latest_inventory_copy_inh_fkey();


SELECT evergreen.upgrade_deps_block_check('1322', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.patron.custom_jquery', 'opac',
    oils_i18n_gettext('opac.patron.custom_jquery',
        'Custom jQuery for the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.patron.custom_jquery',
        'Custom jQuery for the OPAC',
        'coust', 'description'),
    'string', NULL);


SELECT evergreen.upgrade_deps_block_check('1323', :eg_version);

-- VIEWS for the oai service
CREATE SCHEMA oai;

-- The view presents a lean table with unique bre.tc-numbers for oai paging;
CREATE VIEW oai.biblio AS
  SELECT
    bre.id                             AS rec_id,
    bre.edit_date AT TIME ZONE 'UTC'   AS datestamp,
    bre.deleted                        AS deleted
  FROM
    biblio.record_entry bre
  ORDER BY
    bre.id;

-- The view presents a lean table with unique are.tc-numbers for oai paging;
CREATE VIEW oai.authority AS
  SELECT
    are.id                           AS rec_id,
    are.edit_date AT TIME ZONE 'UTC' AS datestamp,
    are.deleted                      AS deleted
  FROM
    authority.record_entry AS are
  ORDER BY
    are.id;

CREATE OR REPLACE function oai.bib_is_visible_at_org_by_copy(bib BIGINT, org INT) RETURNS BOOL AS $F$
WITH corgs AS (SELECT array_agg(id) AS list FROM actor.org_unit_descendants(org))
  SELECT EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache, corgs WHERE vis_attr_vector @@ search.calculate_visibility_attribute_test('circ_lib', corgs.list)::query_int AND bib=record)
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE function oai.bib_is_visible_at_org_by_luri(bib BIGINT, org INT) RETURNS BOOL AS $F$
WITH lorgs AS(SELECT array_agg(id) AS list FROM actor.org_unit_ancestors(org))
  SELECT EXISTS (SELECT 1 FROM biblio.record_entry, lorgs WHERE vis_attr_vector @@ search.calculate_visibility_attribute_test('luri_org', lorgs.list)::query_int AND bib=id)
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE function oai.bib_is_visible_by_source(bib BIGINT, src TEXT) RETURNS BOOL AS $F$
  SELECT EXISTS (SELECT 1 FROM biblio.record_entry b JOIN config.bib_source s ON (b.source = s.id) WHERE transcendant AND s.source = src AND bib=b.id)
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE function oai.auth_is_visible_by_axis(auth BIGINT, ax TEXT) RETURNS BOOL AS $F$
  SELECT EXISTS (SELECT 1 FROM authority.browse_axis_authority_field_map m JOIN authority.simple_heading r on (r.atag = m.field AND r.record = auth AND m.axis = ax))
$F$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('1324', :eg_version);

CREATE TABLE action_trigger.alternate_template (
      id               SERIAL,
      event_def        INTEGER REFERENCES action_trigger.event_definition(id) INITIALLY DEFERRED,
      template         TEXT,
      active           BOOLEAN DEFAULT TRUE,
      message_title    TEXT,
      message_template TEXT,
      locale           TEXT REFERENCES config.i18n_locale(code) INITIALLY DEFERRED,
      UNIQUE (event_def,locale)
);

ALTER TABLE actor.usr ADD COLUMN locale TEXT REFERENCES config.i18n_locale(code) INITIALLY DEFERRED;

ALTER TABLE action_trigger.event_output ADD COLUMN locale TEXT;


SELECT evergreen.upgrade_deps_block_check('1325', :eg_version);

UPDATE config.xml_transform SET xslt=$XSLT$<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:mads="http://www.loc.gov/mads/v2"
	xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:marc="http://www.loc.gov/MARC21/slim"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="marc">
	<xsl:output method="xml" indent="yes" encoding="UTF-8"/>
	<xsl:strip-space elements="*"/>

	<xsl:variable name="ascii">
		<xsl:text> !"#$%&amp;'()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~</xsl:text>
	</xsl:variable>

	<xsl:variable name="latin1">
		<xsl:text> ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ</xsl:text>
	</xsl:variable>
	<!-- Characters that usually don't need to be escaped -->
	<xsl:variable name="safe">
		<xsl:text>!'()*-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~</xsl:text>
	</xsl:variable>

	<xsl:variable name="hex">0123456789ABCDEF</xsl:variable>


	<xsl:template name="datafield">
		<xsl:param name="tag"/>
		<xsl:param name="ind1">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="ind2">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="subfields"/>
		<xsl:element name="marc:datafield">
			<xsl:attribute name="tag">
				<xsl:value-of select="$tag"/>
			</xsl:attribute>
			<xsl:attribute name="ind1">
				<xsl:value-of select="$ind1"/>
			</xsl:attribute>
			<xsl:attribute name="ind2">
				<xsl:value-of select="$ind2"/>
			</xsl:attribute>
			<xsl:copy-of select="$subfields"/>
		</xsl:element>
	</xsl:template>

	<xsl:template name="subfieldSelect">
		<xsl:param name="codes">abcdefghijklmnopqrstuvwxyz</xsl:param>
		<xsl:param name="delimeter">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($codes, @code)">
					<xsl:value-of select="text()"/>
					<xsl:value-of select="$delimeter"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
	</xsl:template>

	<xsl:template name="buildSpaces">
		<xsl:param name="spaces"/>
		<xsl:param name="char">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:if test="$spaces>0">
			<xsl:value-of select="$char"/>
			<xsl:call-template name="buildSpaces">
				<xsl:with-param name="spaces" select="$spaces - 1"/>
				<xsl:with-param name="char" select="$char"/>
			</xsl:call-template>
		</xsl:if>
	</xsl:template>

	<xsl:template name="chopPunctuation">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/ </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationFront">
		<xsl:param name="chopString"/>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains('.:,;/[ ', substring($chopString,1,1))">
				<xsl:call-template name="chopPunctuationFront">
					<xsl:with-param name="chopString" select="substring($chopString,2,$length - 1)"
					/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationBack">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/] </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<!-- nate added 12/14/2007 for lccn.loc.gov: url encode ampersand, etc. -->
	<xsl:template name="url-encode">

		<xsl:param name="str"/>

		<xsl:if test="$str">
			<xsl:variable name="first-char" select="substring($str,1,1)"/>
			<xsl:choose>
				<xsl:when test="contains($safe,$first-char)">
					<xsl:value-of select="$first-char"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:variable name="codepoint">
						<xsl:choose>
							<xsl:when test="contains($ascii,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($ascii,$first-char)) + 32"
								/>
							</xsl:when>
							<xsl:when test="contains($latin1,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($latin1,$first-char)) + 160"/>
								<!-- was 160 -->
							</xsl:when>
							<xsl:otherwise>
								<xsl:message terminate="no">Warning: string contains a character
									that is out of range! Substituting "?".</xsl:message>
								<xsl:text>63</xsl:text>
							</xsl:otherwise>
						</xsl:choose>
					</xsl:variable>
					<xsl:variable name="hex-digit1"
						select="substring($hex,floor($codepoint div 16) + 1,1)"/>
					<xsl:variable name="hex-digit2" select="substring($hex,$codepoint mod 16 + 1,1)"/>
					<!-- <xsl:value-of select="concat('%',$hex-digit2)"/> -->
					<xsl:value-of select="concat('%',$hex-digit1,$hex-digit2)"/>
				</xsl:otherwise>
			</xsl:choose>
			<xsl:if test="string-length($str) &gt; 1">
				<xsl:call-template name="url-encode">
					<xsl:with-param name="str" select="substring($str,2)"/>
				</xsl:call-template>
			</xsl:if>
		</xsl:if>
	</xsl:template>


<!--
2.15  reversed genre and setAuthority template order under relatedTypeAttribute                       tmee 11/13/2018
2.14    Fixed bug in mads:geographic attributes syntax                                      ws   05/04/2016		
2.13	fixed repeating <geographic>														tmee 01/31/2014
2.12	added $2 authority for <classification>												tmee 09/18/2012
2.11	added delimiters between <classification> subfields									tmee 09/18/2012
2.10	fixed type="other" and type="otherType" for mads:related							tmee 09/16/2011
2.09	fixed professionTerm and genreTerm empty tag error									tmee 09/16/2011
2.08	fixed marc:subfield @code='i' matching error										tmee 09/16/2011
2.07	fixed 555 duplication error															tmee 08/10/2011	
2.06	fixed topic subfield error															tmee 08/10/2011	
2.05	fixed title subfield error															tmee 06/20/2011	
2.04	fixed geographicSubdivision mapping for authority element							tmee 06/16/2011
2.03	added classification for 053, 055, 060, 065, 070, 080, 082, 083, 086, 087			tmee 06/03/2011		
2.02	added descriptionStandard for 008/10												tmee 04/27/2011
2.01	added extensions for 046, 336, 370, 374, 375, 376									tmee 04/08/2011
2.00	redefined imported MODS elements in version 1.0 to MADS elements in version 2.0		tmee 02/08/2011
1.08	added 372 subfields $a $s $t for <fieldOfActivity>									tmee 06/24/2010
1.07	removed role/roleTerm 100, 110, 111, 400, 410, 411, 500, 510, 511, 700, 710, 711	tmee 06/24/2010
1.06	added strip-space																	tmee 06/24/2010
1.05	added subfield $a for 130, 430, 530													tmee 06/21/2010
1.04	fixed 550 z omission																ntra 08/11/2008
1.03	removed duplication of 550 $a text													tmee 11/01/2006
1.02	fixed namespace references between mads and mods									ntra 10/06/2006
1.01	revised																				rgue/jrad 11/29/05
1.00	adapted from MARC21Slim2MODS3.xsl													ntra 07/06/05
-->

	<!-- authority attribute defaults to 'naf' if not set using this authority parameter, for <authority> descriptors: name, titleInfo, geographic -->
	<xsl:param name="authority"/>
	<xsl:variable name="auth">
		<xsl:choose>
			<xsl:when test="$authority">
				<xsl:value-of select="$authority"/>
			</xsl:when>
			<xsl:otherwise>naf</xsl:otherwise>
		</xsl:choose>
	</xsl:variable>
	<xsl:variable name="controlField008" select="marc:controlfield[@tag='008']"/>
	<xsl:variable name="controlField008-06"
		select="substring(descendant-or-self::marc:controlfield[@tag=008],7,1)"/>
	<xsl:variable name="controlField008-11"
		select="substring(descendant-or-self::marc:controlfield[@tag=008],12,1)"/>
	<xsl:variable name="controlField008-14"
		select="substring(descendant-or-self::marc:controlfield[@tag=008],15,1)"/>
	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="descendant-or-self::marc:collection">
				<mads:madsCollection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
					xsi:schemaLocation="http://www.loc.gov/mads/v2 http://www.loc.gov/standards/mads/v2/mads-2-0.xsd">
					<xsl:for-each select="descendant-or-self::marc:collection/marc:record">
						<mads:mads version="2.0">
							<xsl:call-template name="marcRecord"/>
						</mads:mads>
					</xsl:for-each>
				</mads:madsCollection>
			</xsl:when>
			<xsl:otherwise>
				<mads:mads version="2.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
					xsi:schemaLocation="http://www.loc.gov/mads/v2 http://www.loc.gov/standards/mads/mads-2-0.xsd">
					<xsl:for-each select="descendant-or-self::marc:record">
						<xsl:call-template name="marcRecord"/>
					</xsl:for-each>
				</mads:mads>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="marcRecord">
		<mads:authority>
			<!-- 2.04 -->
			<xsl:choose>
				<xsl:when test="$controlField008-06='d'">
					<xsl:attribute name="geographicSubdivision">
						<xsl:text>direct</xsl:text>
					</xsl:attribute>
				</xsl:when>
				<xsl:when test="$controlField008-06='i'">
					<xsl:attribute name="geographicSubdivision">
						<xsl:text>indirect</xsl:text>
					</xsl:attribute>
				</xsl:when>
				<xsl:when test="$controlField008-06='n'">
					<xsl:attribute name="geographicSubdivision">
						<xsl:text>not applicable</xsl:text>
					</xsl:attribute>
				</xsl:when>
			</xsl:choose>
			
			<xsl:apply-templates select="marc:datafield[100 &lt;= @tag  and @tag &lt; 200]"/>		
		</mads:authority>

		<!-- related -->
		<xsl:apply-templates
			select="marc:datafield[500 &lt;= @tag and @tag &lt;= 585]|marc:datafield[700 &lt;= @tag and @tag &lt;= 785]"/>

		<!-- variant -->
		<xsl:apply-templates select="marc:datafield[400 &lt;= @tag and @tag &lt;= 485]"/>

		<!-- notes -->
		<xsl:apply-templates select="marc:datafield[667 &lt;= @tag and @tag &lt;= 688]"/>

		<!-- url -->
		<xsl:apply-templates select="marc:datafield[@tag=856]"/>
		<xsl:apply-templates select="marc:datafield[@tag=010]"/>
		<xsl:apply-templates select="marc:datafield[@tag=024]"/>
		<xsl:apply-templates select="marc:datafield[@tag=372]"/>
		
		<!-- classification -->
		<xsl:apply-templates select="marc:datafield[@tag=053]"/>
		<xsl:apply-templates select="marc:datafield[@tag=055]"/>
		<xsl:apply-templates select="marc:datafield[@tag=060]"/>
		<xsl:apply-templates select="marc:datafield[@tag=065]"/>
		<xsl:apply-templates select="marc:datafield[@tag=070]"/>
		<xsl:apply-templates select="marc:datafield[@tag=080]"/>
		<xsl:apply-templates select="marc:datafield[@tag=082]"/>
		<xsl:apply-templates select="marc:datafield[@tag=083]"/>
		<xsl:apply-templates select="marc:datafield[@tag=086]"/>
		<xsl:apply-templates select="marc:datafield[@tag=087]"/>

		<!-- affiliation-->
		<xsl:for-each select="marc:datafield[@tag=373]">
			<mads:affiliation>
				<mads:position>
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</mads:position>
				<mads:dateValid point="start">
					<xsl:value-of select="marc:subfield[@code='s']"/>
				</mads:dateValid>
				<mads:dateValid point="end">
					<xsl:value-of select="marc:subfield[@code='t']"/>
				</mads:dateValid>
			</mads:affiliation>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=371]">
			<mads:affiliation>
				<mads:address>
					<mads:street>
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</mads:street>
					<mads:city>
						<xsl:value-of select="marc:subfield[@code='b']"/>
					</mads:city>
					<mads:state>
						<xsl:value-of select="marc:subfield[@code='c']"/>
					</mads:state>
					<mads:country>
						<xsl:value-of select="marc:subfield[@code='d']"/>
					</mads:country>
					<mads:postcode>
						<xsl:value-of select="marc:subfield[@code='e']"/>
					</mads:postcode>
				</mads:address>
				<mads:email>
					<xsl:value-of select="marc:subfield[@code='m']"/>
				</mads:email>
			</mads:affiliation>
		</xsl:for-each>

		<!-- extension-->
		<xsl:for-each select="marc:datafield[@tag=336]">
			<mads:extension>
				<mads:contentType>
					<mads:contentType type="text">
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</mads:contentType>
					<mads:contentType type="code">
						<xsl:value-of select="marc:subfield[@code='b']"/>
					</mads:contentType>
				</mads:contentType>
			</mads:extension>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=374]">
			<mads:extension>
				<mads:profession>
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='a']">
							<mads:professionTerm>
								<xsl:value-of select="marc:subfield[@code='a']"/>
							</mads:professionTerm>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='s']">
							<mads:dateValid point="start">
								<xsl:value-of select="marc:subfield[@code='s']"/>
							</mads:dateValid>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='t']">
							<mads:dateValid point="end">
								<xsl:value-of select="marc:subfield[@code='t']"/>
							</mads:dateValid>
						</xsl:when>
					</xsl:choose>
				</mads:profession>
			</mads:extension>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=375]">
			<mads:extension>
				<mads:gender>
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='a']">
							<mads:genderTerm>
								<xsl:value-of select="marc:subfield[@code='a']"/>
							</mads:genderTerm>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='s']">
							<mads:dateValid point="start">
								<xsl:value-of select="marc:subfield[@code='s']"/>
							</mads:dateValid>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='t']">
							<mads:dateValid point="end">
								<xsl:value-of select="marc:subfield[@code='t']"/>
							</mads:dateValid>
						</xsl:when>
					</xsl:choose>
				</mads:gender>
			</mads:extension>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=376]">
			<mads:extension>
				<mads:familyInformation>
					<mads:typeOfFamily>
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</mads:typeOfFamily>
					<mads:nameOfProminentMember>
						<xsl:value-of select="marc:subfield[@code='b']"/>
					</mads:nameOfProminentMember>
					<mads:hereditaryTitle>
						<xsl:value-of select="marc:subfield[@code='c']"/>
					</mads:hereditaryTitle>
					<mads:dateValid point="start">
						<xsl:value-of select="marc:subfield[@code='s']"/>
					</mads:dateValid>
					<mads:dateValid point="end">
						<xsl:value-of select="marc:subfield[@code='t']"/>
					</mads:dateValid>
				</mads:familyInformation>
			</mads:extension>
		</xsl:for-each>

		<mads:recordInfo>
			<mads:recordOrigin>Converted from MARCXML to MADS version 2.0 (Revision 2.13)</mads:recordOrigin>
			<!-- <xsl:apply-templates select="marc:datafield[@tag=024]"/> -->

			<xsl:apply-templates select="marc:datafield[@tag=040]/marc:subfield[@code='a']"/>
			<xsl:apply-templates select="marc:controlfield[@tag=005]"/>
			<xsl:apply-templates select="marc:controlfield[@tag=001]"/>
			<xsl:apply-templates select="marc:datafield[@tag=040]/marc:subfield[@code='b']"/>
			<xsl:apply-templates select="marc:datafield[@tag=040]/marc:subfield[@code='e']"/>
			<xsl:for-each select="marc:controlfield[@tag=008]">
				<xsl:if test="substring(.,11,1)='a'">
					<mads:descriptionStandard>
						<xsl:text>earlier rules</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='b'">
					<mads:descriptionStandard>
						<xsl:text>aacr1</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='c'">
					<mads:descriptionStandard>
						<xsl:text>aacr2</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='d'">
					<mads:descriptionStandard>
						<xsl:text>aacr2 compatible</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='z'">
					<mads:descriptionStandard>
						<xsl:text>other rules</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
			</xsl:for-each>
		</mads:recordInfo>
	</xsl:template>

	<!-- start of secondary templates -->

	<!-- ======== xlink ======== -->

	<!-- <xsl:template name="uri"> 
    <xsl:for-each select="marc:subfield[@code='0']">
      <xsl:attribute name="xlink:href">
	<xsl:value-of select="."/>
      </xsl:attribute>
    </xsl:for-each>
     </xsl:template> 
   -->
	<xsl:template match="marc:subfield[@code='i']">
		<xsl:attribute name="otherType">
			<xsl:value-of select="."/>
		</xsl:attribute>
	</xsl:template>

	<!-- No role/roleTerm mapped in MADS 06/24/2010
	<xsl:template name="role">
		<xsl:for-each select="marc:subfield[@code='e']">
			<mads:role>
				<mads:roleTerm type="text">
					<xsl:value-of select="."/>
				</mads:roleTerm>
			</mads:role>
		</xsl:for-each>
	</xsl:template>
-->

	<xsl:template name="part">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">n</xsl:with-param>
				<xsl:with-param name="anyCodes">n</xsl:with-param>
				<xsl:with-param name="afterCodes">fghkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fghkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<mads:partNumber>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partNumber"/>
				</xsl:call-template>
			</mads:partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<mads:partName>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partName"/>
				</xsl:call-template>
			</mads:partName>
		</xsl:if>
	</xsl:template>

	<xsl:template name="nameABCDN">
		<xsl:for-each select="marc:subfield[@code='a']">
			<mads:namePart>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</mads:namePart>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='b']">
			<mads:namePart>
				<xsl:value-of select="."/>
			</mads:namePart>
		</xsl:for-each>
		<xsl:if
			test="marc:subfield[@code='c'] or marc:subfield[@code='d'] or marc:subfield[@code='n']">
			<mads:namePart>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">cdn</xsl:with-param>
				</xsl:call-template>
			</mads:namePart>
		</xsl:if>
	</xsl:template>

	<xsl:template name="nameABCDQ">
		<mads:namePart>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">aq</xsl:with-param>
					</xsl:call-template>
				</xsl:with-param>
			</xsl:call-template>
		</mads:namePart>
		<xsl:call-template name="termsOfAddress"/>
		<xsl:call-template name="nameDate"/>
	</xsl:template>

	<xsl:template name="nameACDENQ">
		<mads:namePart>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">acdenq</xsl:with-param>
			</xsl:call-template>
		</mads:namePart>
	</xsl:template>

	<xsl:template name="nameDate">
		<xsl:for-each select="marc:subfield[@code='d']">
			<mads:namePart type="date">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</mads:namePart>
		</xsl:for-each>
	</xsl:template>

	<xsl:template name="specialSubfieldSelect">
		<xsl:param name="anyCodes"/>
		<xsl:param name="axis"/>
		<xsl:param name="beforeCodes"/>
		<xsl:param name="afterCodes"/>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if
					test="contains($anyCodes, @code) or (contains($beforeCodes,@code) and following-sibling::marc:subfield[@code=$axis]) or (contains($afterCodes,@code) and preceding-sibling::marc:subfield[@code=$axis])">
					<xsl:value-of select="text()"/>
					<xsl:text> </xsl:text>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
	</xsl:template>

	<xsl:template name="termsOfAddress">
		<xsl:if test="marc:subfield[@code='b' or @code='c']">
			<mads:namePart type="termsOfAddress">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">bc</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</mads:namePart>
		</xsl:if>
	</xsl:template>

	<xsl:template name="displayLabel">
		<xsl:if test="marc:subfield[@code='z']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='z']"/>
			</xsl:attribute>
		</xsl:if>
		<xsl:if test="marc:subfield[@code='3']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='3']"/>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>

	<xsl:template name="isInvalid">
		<xsl:if test="@code='z'">
			<xsl:attribute name="invalid">yes</xsl:attribute>
		</xsl:if>
	</xsl:template>

	<xsl:template name="sub2Attribute">
		<!-- 024 -->
		<xsl:if test="../marc:subfield[@code='2']">
			<xsl:attribute name="type">
				<xsl:value-of select="../marc:subfield[@code='2']"/>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>

	<xsl:template match="marc:controlfield[@tag=001]">
		<mads:recordIdentifier>
			<xsl:if test="../marc:controlfield[@tag=003]">
				<xsl:attribute name="source">
					<xsl:value-of select="../marc:controlfield[@tag=003]"/>
				</xsl:attribute>
			</xsl:if>
			<xsl:value-of select="."/>
		</mads:recordIdentifier>
	</xsl:template>

	<xsl:template match="marc:controlfield[@tag=005]">
		<mads:recordChangeDate encoding="iso8601">
			<xsl:value-of select="."/>
		</mads:recordChangeDate>
	</xsl:template>

	<xsl:template match="marc:controlfield[@tag=008]">
		<mads:recordCreationDate encoding="marc">
			<xsl:value-of select="substring(.,1,6)"/>
		</mads:recordCreationDate>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=010]">
		<xsl:for-each select="marc:subfield">
			<mads:identifier type="lccn">
				<xsl:call-template name="isInvalid"/>
				<xsl:value-of select="."/>
			</mads:identifier>
		</xsl:for-each>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=024]">
		<xsl:for-each select="marc:subfield[not(@code=2)]">
			<mads:identifier>
				<xsl:call-template name="isInvalid"/>
				<xsl:call-template name="sub2Attribute"/>
				<xsl:value-of select="."/>
			</mads:identifier>
		</xsl:for-each>
	</xsl:template>

	<!-- ========== 372 ========== -->
	<xsl:template match="marc:datafield[@tag=372]">
		<mads:fieldOfActivity>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">a</xsl:with-param>
			</xsl:call-template>
			<xsl:text>-</xsl:text>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">st</xsl:with-param>
			</xsl:call-template>
		</mads:fieldOfActivity>
	</xsl:template>


	<!-- ========== 040 ========== -->
	<xsl:template match="marc:datafield[@tag=040]/marc:subfield[@code='a']">
		<mads:recordContentSource authority="marcorg">
			<xsl:value-of select="."/>
		</mads:recordContentSource>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=040]/marc:subfield[@code='b']">
		<mads:languageOfCataloging>
			<mads:languageTerm authority="iso639-2b" type="code">
				<xsl:value-of select="."/>
			</mads:languageTerm>
		</mads:languageOfCataloging>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=040]/marc:subfield[@code='e']">
		<mads:descriptionStandard>
			<xsl:value-of select="."/>
		</mads:descriptionStandard>
	</xsl:template>
	
	<!-- ========== classification 2.03 ========== -->
	
	<xsl:template match="marc:datafield[@tag=053]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	
	<xsl:template match="marc:datafield[@tag=055]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	
	<xsl:template match="marc:datafield[@tag=060]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=065]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=070]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=080]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=082]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=083]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=086]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=087]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	

	<!-- ========== names  ========== -->
	<xsl:template match="marc:datafield[@tag=100]">
		<mads:name type="personal">
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="nameABCDQ"/>
		</mads:name>
		<xsl:apply-templates select="*[marc:subfield[not(contains('abcdeq',@code))]]"/>
		<xsl:call-template name="title"/>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=110]">
		<mads:name type="corporate">
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="nameABCDN"/>
		</mads:name>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=111]">
		<mads:name type="conference">
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="nameACDENQ"/>
		</mads:name>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=400]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<mads:name type="personal">
				<xsl:call-template name="nameABCDQ"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
			<xsl:call-template name="title"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=410]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<mads:name type="corporate">
				<xsl:call-template name="nameABCDN"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=411]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<mads:name type="conference">
				<xsl:call-template name="nameACDENQ"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=500]|marc:datafield[@tag=700]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<mads:name type="personal">
				<xsl:call-template name="setAuthority"/>
				<xsl:call-template name="nameABCDQ"/>
			</mads:name>
			<xsl:call-template name="title"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=510]|marc:datafield[@tag=710]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<mads:name type="corporate">
				<xsl:call-template name="setAuthority"/>
				<xsl:call-template name="nameABCDN"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=511]|marc:datafield[@tag=711]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<mads:name type="conference">
				<xsl:call-template name="setAuthority"/>
				<xsl:call-template name="nameACDENQ"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<!-- ========== titles  ========== -->
	<xsl:template match="marc:datafield[@tag=130]">
		<xsl:call-template name="uniform-title"/>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=430]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="uniform-title"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=530]|marc:datafield[@tag=730]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="uniform-title"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<xsl:template name="title">
		<xsl:variable name="hasTitle">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="(contains('tfghklmors',@code) )">
					<xsl:value-of select="@code"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length($hasTitle) &gt; 0 ">
			<mads:titleInfo>
				<xsl:call-template name="setAuthority"/>
				<mads:title>
					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if test="(contains('atfghklmors',@code) )">
								<xsl:value-of select="text()"/>
								<xsl:text> </xsl:text>
							</xsl:if>
						</xsl:for-each>
					</xsl:variable>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
						</xsl:with-param>
					</xsl:call-template>
				</mads:title>
				<xsl:call-template name="part"/>
				<!-- <xsl:call-template name="uri"/> -->
			</mads:titleInfo>
		</xsl:if>
	</xsl:template>

	<xsl:template name="uniform-title">
		<xsl:variable name="hasTitle">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="(contains('atfghklmors',@code) )">
					<xsl:value-of select="@code"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length($hasTitle) &gt; 0 ">
			<mads:titleInfo>
				<xsl:call-template name="setAuthority"/>
				<mads:title>
					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if test="(contains('adfghklmors',@code) )">
								<xsl:value-of select="text()"/>
								<xsl:text> </xsl:text>
							</xsl:if>
						</xsl:for-each>
					</xsl:variable>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
						</xsl:with-param>
					</xsl:call-template>
				</mads:title>
				<xsl:call-template name="part"/>
				<!-- <xsl:call-template name="uri"/> -->
			</mads:titleInfo>
		</xsl:if>
	</xsl:template>


	<!-- ========== topics  ========== -->
	<xsl:template match="marc:subfield[@code='x']">
		<mads:topic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:topic>
	</xsl:template>
	
	<!-- 2.06 fix -->
	<xsl:template
		match="marc:datafield[@tag=150][marc:subfield[@code='a' or @code='b']]|marc:datafield[@tag=180][marc:subfield[@code='x']]">
		<xsl:call-template name="topic"/>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=450][marc:subfield[@code='a' or @code='b']]|marc:datafield[@tag=480][marc:subfield[@code='x']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="topic"/>
		</mads:variant>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=550 or @tag=750][marc:subfield[@code='a' or @code='b']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<xsl:call-template name="topic"/>
			<xsl:apply-templates select="marc:subfield[@code='z']"/>
		</mads:related>
	</xsl:template>
	<xsl:template name="topic">
		<mads:topic>
			<xsl:call-template name="setAuthority"/>
			<!-- tmee2006 dedupe 550a
			<xsl:if test="@tag=550 or @tag=750">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</xsl:if>	
			-->
			<xsl:choose>
				<xsl:when test="@tag=180 or @tag=480 or @tag=580 or @tag=780">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:apply-templates select="marc:subfield[@code='x']"/>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:when>
			</xsl:choose>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<xsl:when test="@tag=180 or @tag=480 or @tag=580 or @tag=780">
							<xsl:apply-templates select="marc:subfield[@code='x']"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ab</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:topic>
	</xsl:template>

	<!-- ========= temporals  ========== -->
	<xsl:template match="marc:subfield[@code='y']">
		<mads:temporal>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:temporal>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=148][marc:subfield[@code='a']]|marc:datafield[@tag=182 ][marc:subfield[@code='y']]">
		<xsl:call-template name="temporal"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=448][marc:subfield[@code='a']]|marc:datafield[@tag=482][marc:subfield[@code='y']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="temporal"/>
		</mads:variant>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=548 or @tag=748][marc:subfield[@code='a']]|marc:datafield[@tag=582 or @tag=782][marc:subfield[@code='y']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<xsl:call-template name="temporal"/>
		</mads:related>
	</xsl:template>
	<xsl:template name="temporal">
		<mads:temporal>
			<xsl:call-template name="setAuthority"/>
			<xsl:if test="@tag=548 or @tag=748">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</xsl:if>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<xsl:when test="@tag=182 or @tag=482 or @tag=582 or @tag=782">
							<xsl:apply-templates select="marc:subfield[@code='y']"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:temporal>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<!-- ========== genre  ========== -->
	<xsl:template match="marc:subfield[@code='v']">
		<mads:genre>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:genre>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=155][marc:subfield[@code='a']]|marc:datafield[@tag=185][marc:subfield[@code='v']]">
		<xsl:call-template name="genre"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=455][marc:subfield[@code='a']]|marc:datafield[@tag=485 ][marc:subfield[@code='v']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="genre"/>
		</mads:variant>
	</xsl:template>
	<!--
	<xsl:template match="marc:datafield[@tag=555]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="uri"/>
			<xsl:call-template name="genre"/>
		</mads:related>
	</xsl:template>
	-->
	<xsl:template
		match="marc:datafield[@tag=555 or @tag=755][marc:subfield[@code='a']]|marc:datafield[@tag=585][marc:subfield[@code='v']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="genre"/>
		</mads:related>
	</xsl:template>
	<xsl:template name="genre">
		<mads:genre>
			<xsl:if test="@tag=555">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</xsl:if>
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<!-- 2.07 fix -->
						<xsl:when test="@tag='555'"/>
						<xsl:when test="@tag=185 or @tag=485 or @tag=585">
							<xsl:apply-templates select="marc:subfield[@code='v']"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:genre>
		<xsl:apply-templates/>
	</xsl:template>

	<!-- ========= geographic  ========== -->
	<xsl:template match="marc:subfield[@code='z']">
		<mads:geographic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:geographic>
	</xsl:template>
	<xsl:template name="geographic">
		<mads:geographic>
			<!-- 2.14 -->
			<xsl:call-template name="setAuthority"/>
			<!-- 2.13 -->
			<xsl:if test="@tag=151 or @tag=551">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</xsl:if>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
						<xsl:if test="@tag=181 or @tag=481 or @tag=581">
								<xsl:apply-templates select="marc:subfield[@code='z']"/>
						</xsl:if>
						<!-- 2.13
							<xsl:choose>
						<xsl:when test="@tag=181 or @tag=481 or @tag=581">
							<xsl:apply-templates select="marc:subfield[@code='z']"/>
						</xsl:when>
					
						<xsl:otherwise>
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:otherwise>
						</xsl:choose>
						-->
				</xsl:with-param>
			</xsl:call-template>
		</mads:geographic>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=151][marc:subfield[@code='a']]|marc:datafield[@tag=181][marc:subfield[@code='z']]">
		<xsl:call-template name="geographic"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=451][marc:subfield[@code='a']]|marc:datafield[@tag=481][marc:subfield[@code='z']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="geographic"/>
		</mads:variant>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=551]|marc:datafield[@tag=581][marc:subfield[@code='z']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<xsl:call-template name="geographic"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=580]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=751][marc:subfield[@code='z']]|marc:datafield[@tag=781][marc:subfield[@code='z']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="geographic"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=755]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="genre"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=780]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=785]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<!-- ========== notes  ========== -->
	<xsl:template match="marc:datafield[667 &lt;= @tag and @tag &lt;= 688]">
		<mads:note>
			<xsl:choose>
				<xsl:when test="@tag=667">
					<xsl:attribute name="type">nonpublic</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=670">
					<xsl:attribute name="type">source</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=675">
					<xsl:attribute name="type">notFound</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=678">
					<xsl:attribute name="type">history</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=681">
					<xsl:attribute name="type">subject example</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=682">
					<xsl:attribute name="type">deleted heading information</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=688">
					<xsl:attribute name="type">application history</xsl:attribute>
				</xsl:when>
			</xsl:choose>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<xsl:when test="@tag=667 or @tag=675">
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:when>
						<xsl:when test="@tag=670 or @tag=678">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ab</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:when test="680 &lt;= @tag and @tag &lt;=688">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ai</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:note>
	</xsl:template>

	<!-- ========== url  ========== -->
	<xsl:template match="marc:datafield[@tag=856][marc:subfield[@code='u']]">
		<mads:url>
			<xsl:if test="marc:subfield[@code='z' or @code='3']">
				<xsl:attribute name="displayLabel">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">z3</xsl:with-param>
					</xsl:call-template>
				</xsl:attribute>
			</xsl:if>
			<xsl:value-of select="marc:subfield[@code='u']"/>
		</mads:url>
	</xsl:template>

	<xsl:template name="relatedTypeAttribute">
		<xsl:choose>
			<xsl:when
				test="@tag=500 or @tag=510 or @tag=511 or @tag=548 or @tag=550 or @tag=551 or @tag=555 or @tag=580 or @tag=581 or @tag=582 or @tag=585">
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='a'">
					<xsl:attribute name="type">earlier</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='b'">
					<xsl:attribute name="type">later</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='t'">
					<xsl:attribute name="type">parentOrg</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='g'">
					<xsl:attribute name="type">broader</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='h'">
					<xsl:attribute name="type">narrower</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='r'">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
				<xsl:if test="contains('fin|', substring(marc:subfield[@code='w'],1,1))">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
			</xsl:when>
			<xsl:when test="@tag=530 or @tag=730">
				<xsl:attribute name="type">other</xsl:attribute>
			</xsl:when>
			<xsl:otherwise>
				<!-- 7xx -->
				<xsl:attribute name="type">equivalent</xsl:attribute>
			</xsl:otherwise>
		</xsl:choose>
		<xsl:apply-templates select="marc:subfield[@code='i']"/>
	</xsl:template>
	


	<xsl:template name="variantTypeAttribute">
		<xsl:choose>
			<xsl:when
				test="@tag=400 or @tag=410 or @tag=411 or @tag=451 or @tag=455 or @tag=480 or @tag=481 or @tag=482 or @tag=485">
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='d'">
					<xsl:attribute name="type">acronym</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='n'">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
				<xsl:if test="contains('fit', substring(marc:subfield[@code='w'],1,1))">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise>
				<!-- 430  -->
				<xsl:attribute name="type">other</xsl:attribute>
			</xsl:otherwise>
		</xsl:choose>
		<xsl:apply-templates select="marc:subfield[@code='i']"/>
	</xsl:template>

	<xsl:template name="setAuthority">
		<xsl:choose>
			<!-- can be called from the datafield or subfield level, so "..//@tag" means
			the tag can be at the subfield's parent level or at the datafields own level -->

			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and (@ind1=0 or @ind1=1) and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>naf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and (@ind1=0 or @ind1=1) and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and (@ind1=0 or @ind1=1) and $controlField008-11='k'">
				<xsl:attribute name="authority">
					<xsl:text>lacnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and @ind1=3 and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and @ind1=3 and $controlField008-11='k' and $controlField008-14='b'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">naf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='k' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>lacnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='k' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>cash</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcshcl</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=100 or ancestor-or-self::marc:datafield/@tag=110 or ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130 or ancestor-or-self::marc:datafield/@tag=151) and $controlField008-11='c'">
				<xsl:attribute name="authority">
					<xsl:text>nlmnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=100 or ancestor-or-self::marc:datafield/@tag=110 or ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130 or ancestor-or-self::marc:datafield/@tag=151) and $controlField008-11='d'">
				<xsl:attribute name="authority">
					<xsl:text>nalnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='r'">
				<xsl:attribute name="authority">
					<xsl:text>aat</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='s'">
				<xsl:attribute name="authority">sears</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='v'">
				<xsl:attribute name="authority">rvm</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='z'">
				<xsl:attribute name="authority">
					<xsl:value-of
						select="../marc:datafield[ancestor-or-self::marc:datafield/@tag=040]/marc:subfield[@code='f']"
					/>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130) and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>naf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130) and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130) and $controlField008-11='k' ">
				<xsl:attribute name="authority">
					<xsl:text>lacnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='a' ">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='a' ">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='c' ">
				<xsl:attribute name="authority">
					<xsl:text>mesh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='d' ">
				<xsl:attribute name="authority">
					<xsl:text>nal</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='k' ">
				<xsl:attribute name="authority">
					<xsl:text>cash</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>naf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='k' and $controlField008-14='a'">
				<xsl:attribute name="authority">lacnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='k' and $controlField008-14='b'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(..//ancestor-or-self::marc:datafield/@tag=180 or ..//ancestor-or-self::marc:datafield/@tag=181 or ..//ancestor-or-self::marc:datafield/@tag=182 or ..//ancestor-or-self::marc:datafield/@tag=185) and $controlField008-11='a'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=700 and (@ind1='0' or @ind1='1') and @ind2='0'">
				<xsl:attribute name="authority">naf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=700 and (@ind1='0' or @ind1='1') and @ind2='5'">
				<xsl:attribute name="authority">lacnaf</xsl:attribute>
			</xsl:when>
			<xsl:when test="ancestor-or-self::marc:datafield/@tag=700 and @ind1='3' and @ind2='0'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when test="ancestor-or-self::marc:datafield/@tag=700 and @ind1='3' and @ind2='5'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(700 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 755 ) and @ind2='1'">
				<xsl:attribute name="authority">lcshcl</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=700 or ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='2'">
				<xsl:attribute name="authority">nlmnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=700 or ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='3'">
				<xsl:attribute name="authority">nalnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(700 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 755 ) and @ind2='6'">
				<xsl:attribute name="authority">rvm</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(700 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 755 ) and @ind2='7'">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='5'">
				<xsl:attribute name="authority">lacnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='0'">
				<xsl:attribute name="authority">naf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='0'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='2'">
				<xsl:attribute name="authority">mesh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='3'">
				<xsl:attribute name="authority">nal</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='5'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
		</xsl:choose>
	</xsl:template>
	<xsl:template match="*"/>
</xsl:stylesheet>$XSLT$ WHERE name = 'mads21';


SELECT evergreen.upgrade_deps_block_check('1310', :eg_version);

DROP AGGREGATE IF EXISTS array_accum(anyelement) CASCADE;


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
