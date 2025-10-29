BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


ALTER TABLE vandelay.import_item_attr_definition
    ADD COLUMN floating TEXT,
    ADD COLUMN loan_duration TEXT,
    ADD COLUMN fine_level TEXT,
    ADD COLUMN age_protect TEXT,
    ADD COLUMN mint_condition TEXT;

ALTER TABLE vandelay.import_item
    ADD COLUMN floating INT,
    ADD COLUMN loan_duration INT,
    ADD COLUMN fine_level INT,
    ADD COLUMN age_protect INT,
    ADD COLUMN mint_condition BOOL;

INSERT INTO vandelay.import_error ( code, description ) VALUES (
    'import.item.invalid.age_protect', oils_i18n_gettext('import.item.invalid.age_protect', 'Invalid Age Protection Rule', 'vie', 'description') ),
(   'import.item.invalid.floating', oils_i18n_gettext('import.item.invalid.floating', 'Invalid Floating Group', 'vie', 'description') );


CREATE OR REPLACE FUNCTION vandelay._ingest_items_xpath_helper (input_text TEXT) RETURNS TEXT AS $$
BEGIN
    RETURN CASE
        WHEN input_text IS NULL THEN 'null()'
        WHEN LENGTH(input_text) = 1 THEN '//*[@code="' || input_text || '"]'
        ELSE '//*' || input_text
    END;

END;
$$ LANGUAGE plpgsql;

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
    age_protect     TEXT;
    floating        TEXT;
    fine_level      TEXT;
    loan_duration   TEXT;
    mint_condition  TEXT;

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

        owning_lib := vandelay._ingest_items_xpath_helper(attr_def.owning_lib);
        circ_lib := vandelay._ingest_items_xpath_helper(attr_def.circ_lib);
        call_number := vandelay._ingest_items_xpath_helper(attr_def.call_number);
        copy_number := vandelay._ingest_items_xpath_helper(attr_def.copy_number);
        status := vandelay._ingest_items_xpath_helper(attr_def.status);
        location := vandelay._ingest_items_xpath_helper(attr_def.location);
        circulate := vandelay._ingest_items_xpath_helper(attr_def.circulate);
        deposit := vandelay._ingest_items_xpath_helper(attr_def.deposit);
        deposit_amount := vandelay._ingest_items_xpath_helper(attr_def.deposit_amount);
        ref := vandelay._ingest_items_xpath_helper(attr_def.ref);
        holdable := vandelay._ingest_items_xpath_helper(attr_def.holdable);
        price := vandelay._ingest_items_xpath_helper(attr_def.price);
        barcode := vandelay._ingest_items_xpath_helper(attr_def.barcode);
        circ_modifier := vandelay._ingest_items_xpath_helper(attr_def.circ_modifier);
        circ_as_type := vandelay._ingest_items_xpath_helper(attr_def.circ_as_type);
        alert_message := vandelay._ingest_items_xpath_helper(attr_def.alert_message);
        opac_visible := vandelay._ingest_items_xpath_helper(attr_def.opac_visible);
        pub_note := vandelay._ingest_items_xpath_helper(attr_def.pub_note);
        priv_note := vandelay._ingest_items_xpath_helper(attr_def.priv_note);
        internal_id := vandelay._ingest_items_xpath_helper(attr_def.internal_id);
        stat_cat_data := vandelay._ingest_items_xpath_helper(attr_def.stat_cat_data);
        parts_data := vandelay._ingest_items_xpath_helper(attr_def.parts_data);
        age_protect := vandelay._ingest_items_xpath_helper(attr_def.age_protect);
        floating := vandelay._ingest_items_xpath_helper(attr_def.floating);
        fine_level := vandelay._ingest_items_xpath_helper(attr_def.fine_level);
        loan_duration := vandelay._ingest_items_xpath_helper(attr_def.loan_duration);
        mint_condition := vandelay._ingest_items_xpath_helper(attr_def.mint_condition);


        xpaths := ARRAY[owning_lib, circ_lib, call_number, copy_number, status, location, circulate,
                        deposit, deposit_amount, ref, holdable, price, barcode, circ_modifier, circ_as_type,
                        alert_message, pub_note, priv_note, internal_id, stat_cat_data, parts_data, opac_visible, 
                        age_protect, floating, fine_level, loan_duration, mint_condition];

        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_tag_to_table( (SELECT marc FROM vandelay.queued_bib_record WHERE id = import_id), attr_def.tag, xpaths)
                            AS t( ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, internal_id TEXT,
                                  stat_cat_data TEXT, parts_data TEXT, opac_vis TEXT,
                                  age_protect TEXT, floating TEXT, fine_level TEXT, loan_duration TEXT, mint_condition TEXT )
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

            
            IF tmp_attr_set.age_protect != '' THEN 
                SELECT id INTO attr_set.age_protect FROM config.rule_age_hold_protect WHERE LOWER(name) = LOWER(tmp_attr_set.age_protect); -- INT
                IF NOT FOUND THEN 
                    attr_set.import_error := 'import.item.invalid.age_protect';
                    attr_set.error_detail := tmp_attr_set.age_protect;
                    RETURN NEXT attr_set; CONTINUE;
                END IF;
            END IF;

            IF tmp_attr_set.floating != '' THEN 
                SELECT id INTO attr_set.floating FROM config.floating_group WHERE LOWER(name) = LOWER(tmp_attr_set.floating); -- INT
                IF NOT FOUND THEN 
                    attr_set.import_error := 'import.item.invalid.floating';
                    attr_set.error_detail := tmp_attr_set.floating;
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

            attr_set.mint_condition :=
                LOWER( SUBSTRING( tmp_attr_set.mint_condition, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.mint_condition) = 'mint_condition'; -- BOOL

            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.internal_id    := tmp_attr_set.internal_id::BIGINT;
            attr_set.stat_cat_data  := tmp_attr_set.stat_cat_data; -- TEXT,
            attr_set.parts_data     := tmp_attr_set.parts_data; -- TEXT,
            attr_set.fine_level     := tmp_attr_set.fine_level::INT;
            attr_set.loan_duration  := tmp_attr_set.loan_duration::INT;


            RETURN NEXT attr_set;

        END LOOP;

    END IF;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;



CREATE OR REPLACE FUNCTION vandelay.ingest_bib_items ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr_def    BIGINT;
    item_data   vandelay.import_item%ROWTYPE;
BEGIN

    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT item_attr_def INTO attr_def FROM vandelay.bib_queue WHERE id = NEW.queue;

    FOR item_data IN SELECT * FROM vandelay.ingest_items( NEW.id::BIGINT, attr_def ) LOOP
        INSERT INTO vandelay.import_item (
            record,
            definition,
            owning_lib,
            circ_lib,
            call_number,
            copy_number,
            status,
            location,
            circulate,
            deposit,
            deposit_amount,
            ref,
            holdable,
            price,
            barcode,
            circ_modifier,
            circ_as_type,
            alert_message,
            pub_note,
            priv_note,
            internal_id,
            opac_visible,
            stat_cat_data,
            parts_data,
            import_error,
            error_detail,
            age_protect,
            floating,
            fine_level,
            loan_duration,
            mint_condition

        ) VALUES (
            NEW.id,
            item_data.definition,
            item_data.owning_lib,
            item_data.circ_lib,
            item_data.call_number,
            item_data.copy_number,
            item_data.status,
            item_data.location,
            item_data.circulate,
            item_data.deposit,
            item_data.deposit_amount,
            item_data.ref,
            item_data.holdable,
            item_data.price,
            item_data.barcode,
            item_data.circ_modifier,
            item_data.circ_as_type,
            item_data.alert_message,
            item_data.pub_note,
            item_data.priv_note,
            item_data.internal_id,
            item_data.opac_visible,
            item_data.stat_cat_data,
            item_data.parts_data,
            item_data.import_error,
            item_data.error_detail,
            item_data.age_protect,
            item_data.floating,
            item_data.fine_level,
            item_data.loan_duration,
            item_data.mint_condition

        );
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;




COMMIT;