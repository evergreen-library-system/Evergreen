--Upgrade Script for 3.16.5 to 3.17-beta3
\set eg_version '''3.17-beta3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.17-beta3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1507', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
    ('notify.sms',   oils_i18n_gettext('notify.sms',   'Text Notices',  'csg', 'label')),
    ('notify.email', oils_i18n_gettext('notify.email', 'Email Notices', 'csg', 'label')),
    ('notify.phone', oils_i18n_gettext('notify.phone', 'Phone Notices', 'csg', 'label')),
    ('notify.print', oils_i18n_gettext('notify.print', 'Print Notices', 'csg', 'label'))
;



SELECT evergreen.upgrade_deps_block_check('1509', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.do_not_retain_year_of_birth_on_aged', 'circ',
    oils_i18n_gettext('circ.do_not_retain_year_of_birth_on_aged',
        'When aging circulations do not retain the year from patron date of birth',
        'cust', 'label'),
    oils_i18n_gettext('circ.do_not_retain_year_of_birth_on_aged',
        'When aging circulations do not retain the year from patron date of birth',
        'cust', 'description'),
    'bool', NULL);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.do_not_retain_post_code_on_aged', 'circ',
    oils_i18n_gettext('circ.do_not_retain_post_code_on_aged',
        'When aging circulations do not retain the patron postal code',
        'cust', 'label'),
    oils_i18n_gettext('circ.do_not_retain_post_code_on_aged',
        'When aging circulations do not retain the patron postal code',
        'cust', 'description'),
    'bool', NULL);


INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'holds.do_not_retain_year_of_birth_on_aged', 'circ',
    oils_i18n_gettext('holds.do_not_retain_year_of_birth_on_aged',
        'When aging holds do not retain the year from patron date of birth',
        'cust', 'label'),
    oils_i18n_gettext('holds.do_not_retain_year_of_birth_on_aged',
        'When aging holds do not retain the year from patron date of birth',
        'cust', 'description'),
    'bool', NULL);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'holds.do_not_retain_post_code_on_aged', 'circ',
    oils_i18n_gettext('holds.do_not_retain_post_code_on_aged',
        'When aging holds do not retain the patron postal code',
        'cust', 'label'),
    oils_i18n_gettext('holds.do_not_retain_post_code_on_aged',
        'When aging holds do not retain the patron postal code',
        'cust', 'description'),
    'bool', NULL);


CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
patron_ou               INTEGER;
kept_year               INTEGER;
kept_postcode           TEXT;
donot_keep_year         BOOLEAN;
donot_keep_postcode     BOOLEAN;
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found  
    FROM action.circulation   
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
    END IF;

    SELECT usr_home_ou FROM action.all_circulation WHERE id = OLD.id INTO patron_ou;

    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'circ.do_not_retain_year_of_birth_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_year;
    IF donot_keep_year IS NULL THEN donot_keep_year = FALSE; END IF; 
        
    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'circ.do_not_retain_post_code_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_postcode;
    IF donot_keep_postcode IS NULL THEN donot_keep_postcode = FALSE; END IF;
        
    IF donot_keep_year = TRUE THEN kept_year = NULL; ELSE kept_year = (SELECT usr_birth_year FROM action.all_circulation WHERE id = OLD.id); END IF;
    IF donot_keep_postcode = TRUE THEN kept_postcode = NULL; ELSE kept_postcode = (SELECT usr_post_code FROM action.all_circulation WHERE id = OLD.id); END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id, kept_postcode, usr_home_ou, usr_profile, kept_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables

    SELECT 'Y' INTO found FROM config.global_flag
        WHERE name = 'history.money.age_with_circs' AND enabled;

    IF found = 'Y' THEN
        PERFORM money.age_billings_and_payments_for_xact(OLD.id);
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.age_hold_on_delete () RETURNS TRIGGER AS $$
DECLARE
patron_ou               INTEGER;
kept_year               INTEGER;
kept_postcode           TEXT;
donot_keep_year         BOOLEAN;
donot_keep_postcode     BOOLEAN;
BEGIN
    -- Archive a copy of the old row to action.aged_hold_request
    SELECT usr_home_ou FROM action.all_hold_request WHERE id = OLD.id INTO patron_ou;

    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'holds.do_not_retain_year_of_birth_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_year;
    IF donot_keep_year IS NULL THEN donot_keep_year = FALSE; END IF;

    SELECT value::BOOLEAN FROM actor.org_unit_setting WHERE name = 'holds.do_not_retain_post_code_on_aged'
    AND org_unit IN (SELECT id FROM actor.org_unit_ancestors(patron_ou)) ORDER BY org_unit DESC LIMIT 1
    INTO donot_keep_postcode;
    IF donot_keep_postcode IS NULL THEN donot_keep_postcode = FALSE; END IF;

    IF donot_keep_year = TRUE THEN kept_year = NULL; ELSE kept_year = (SELECT usr_birth_year FROM action.all_hold_request WHERE id = OLD.id); END IF;
    IF donot_keep_postcode = TRUE THEN kept_postcode = NULL; ELSE kept_postcode = (SELECT usr_post_code FROM action.all_hold_request WHERE id = OLD.id); END IF;

    INSERT INTO action.aged_hold_request
           (usr_post_code,
            usr_home_ou,
            usr_profile,
            usr_birth_year,
            staff_placed,
            id,
            request_time,
            capture_time,
            fulfillment_time,
            checkin_time,
            return_time,
            prev_check_time,
            expire_time,
            cancel_time,
            cancel_cause,
            cancel_note,
            target,
            current_copy,
            fulfillment_staff,
            fulfillment_lib,
            request_lib,
            selection_ou,
            selection_depth,
            pickup_lib,
            hold_type,
            holdable_formats,
            phone_notify,
            email_notify,
            sms_notify,
            frozen,
            thaw_date,
            shelf_time,
            cut_in_line,
            mint_condition,
            shelf_expire_time,
            current_shelf_lib,
            behind_desk)
            SELECT
                 kept_postcode,
                 usr_home_ou,
                 usr_profile,
                 kept_year,
                 staff_placed,
                 id,
                 request_time,
                 capture_time,
                 fulfillment_time,
                 checkin_time,
                 return_time,
                 prev_check_time,
                 expire_time,
                 cancel_time,
                 cancel_cause,
                 cancel_note,
                 target,
                 current_copy,
                 fulfillment_staff,
                 fulfillment_lib,
                 request_lib,
                 selection_ou,
                 selection_depth,
                 pickup_lib,
                 hold_type,
                 holdable_formats,
                 phone_notify,
                 email_notify,
                 sms_notify,
                 frozen,
                 thaw_date,
                 shelf_time,
                 cut_in_line,
                 mint_condition,
                 shelf_expire_time,
                 current_shelf_lib,
                 behind_desk
              FROM action.all_hold_request WHERE id = OLD.id;

          RETURN OLD;
      END;
      $$ LANGUAGE 'plpgsql';





SELECT evergreen.upgrade_deps_block_check('1511', :eg_version);


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





SELECT evergreen.upgrade_deps_block_check('1512', :eg_version);

CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

    -- action_trigger.event (even doing this, event_output may--and probably does--contain PII and should have a retention/removal policy)
    UPDATE action_trigger.event SET context_user = dest_usr WHERE context_user = src_usr;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	UPDATE action.hold_request SET canceled_by = dest_usr WHERE canceled_by = src_usr;
	UPDATE action.hold_request_reset_reason_entry SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;
	UPDATE action.curbside SET notes = NULL WHERE patron = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;
	DELETE FROM actor.usr_privacy_waiver WHERE usr = src_usr;
	DELETE FROM actor.usr_message WHERE usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;

	-- LP#885270: Addresses owned by src_usr that are referenced by other
	-- users (as billing_address or mailing_address) cannot be deleted.
	-- Reassign ownership of those addresses to one of the referencing
	-- users so the address is preserved for them.
	UPDATE actor.usr_address addr SET usr = sub.new_owner
	FROM (
		SELECT a.id, (
			SELECT u.id FROM actor.usr u
			WHERE (u.billing_address = a.id OR u.mailing_address = a.id)
				AND u.id != src_usr
			LIMIT 1
		) AS new_owner
		FROM actor.usr_address a
		WHERE a.usr = src_usr
			AND EXISTS (
				SELECT 1 FROM actor.usr u
				WHERE (u.billing_address = a.id OR u.mailing_address = a.id)
					AND u.id != src_usr
			)
	) sub
	WHERE addr.id = sub.id;

	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_message SET title = 'purged', message = 'purged', read_date = NOW() WHERE usr = src_usr;
	DELETE FROM actor.usr_message WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;
	UPDATE actor.usr_message SET editor = dest_usr WHERE editor = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1513', :eg_version);

ALTER TABLE config.i18n_locale
ADD COLUMN staff_client BOOL NOT NULL DEFAULT FALSE;

UPDATE config.i18n_locale SET staff_client = TRUE WHERE code = 'en-US';


SELECT evergreen.upgrade_deps_block_check('1514', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.hold_matrix_matchpoint', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.hold_matrix_matchpoint',
        'Grid Config: admin.config.hold_matrix_matchpoint',
        'cwst', 'label'
    )
);

DROP INDEX config.ccmm_once_per_paramset;
DROP INDEX config.chmm_once_per_paramset;

ALTER TABLE config.circ_matrix_weights
    ADD COLUMN org_lasso NUMERIC(6,2) NOT NULL DEFAULT 10.0,
    ADD COLUMN copy_circ_lasso NUMERIC(6,2) NOT NULL DEFAULT 8.0,
    ADD COLUMN copy_owning_lasso NUMERIC(6,2) NOT NULL DEFAULT 8.0,
    ADD COLUMN user_home_lasso NUMERIC(6,2) NOT NULL DEFAULT 8.0;

ALTER TABLE config.hold_matrix_weights
    ADD COLUMN user_home_lasso NUMERIC(6,2) NOT NULL DEFAULT 5.0,
    ADD COLUMN request_lasso NUMERIC(6,2) NOT NULL DEFAULT 5.0,
    ADD COLUMN pickup_lasso NUMERIC(6,2) NOT NULL DEFAULT 5.0,
    ADD COLUMN item_owning_lasso NUMERIC(6,2) NOT NULL DEFAULT 5.0,
    ADD COLUMN item_circ_lasso NUMERIC(6,2) NOT NULL DEFAULT 5.0;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN org_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN copy_circ_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN copy_owning_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN user_home_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.hold_matrix_matchpoint
    ADD COLUMN user_home_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN request_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN pickup_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN item_owning_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN item_circ_lasso INT REFERENCES actor.org_lasso (id) DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX ccmm_once_per_paramset ON config.circ_matrix_matchpoint (org_unit, grp, COALESCE(circ_modifier, ''), COALESCE(copy_location::TEXT, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level,''), COALESCE(marc_vr_format, ''), COALESCE(copy_circ_lib::TEXT, ''), COALESCE(copy_owning_lib::TEXT, ''), COALESCE(user_home_ou::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(is_renewal::TEXT, ''), COALESCE(usr_age_lower_bound, '2 seconds'), COALESCE(usr_age_upper_bound, '0 seconds'), COALESCE(item_age, '0 seconds'),COALESCE(org_lasso::TEXT,''),COALESCE(copy_circ_lasso::TEXT, ''), COALESCE(copy_owning_lasso::TEXT, ''), COALESCE(user_home_lasso::TEXT, '')) WHERE active;

CREATE UNIQUE INDEX chmm_once_per_paramset ON config.hold_matrix_matchpoint (COALESCE(user_home_ou::TEXT, ''), COALESCE(request_ou::TEXT, ''), COALESCE(pickup_ou::TEXT, ''), COALESCE(item_owning_ou::TEXT, ''), COALESCE(item_circ_ou::TEXT, ''), COALESCE(user_home_lasso::TEXT, ''), COALESCE(request_lasso::TEXT, ''), COALESCE(pickup_lasso::TEXT, ''), COALESCE(item_owning_lasso::TEXT, ''), COALESCE(item_circ_lasso::TEXT, ''), COALESCE(usr_grp::TEXT, ''), COALESCE(requestor_grp::TEXT, ''), COALESCE(circ_modifier, ''), COALESCE(copy_location::TEXT, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level, ''), COALESCE(marc_vr_format, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(item_age, '0 seconds')) WHERE active;

CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, item_object asset.copy, user_object actor.usr, renewal BOOL ) RETURNS action.found_circ_matrix_matchpoint AS $func$
DECLARE
    cn_object       asset.call_number%ROWTYPE;
    rec_descriptor  metabib.rec_descriptor%ROWTYPE;
    cur_matchpoint  config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint      config.circ_matrix_matchpoint%ROWTYPE;
    weights         config.circ_matrix_weights%ROWTYPE;
    user_age        INTERVAL;
    my_item_age     INTERVAL;
    denominator     NUMERIC(6,2);
    row_list        INT[];
    result          action.found_circ_matrix_matchpoint;
BEGIN
    -- Assume failure
    result.success = false;

    -- Fetch useful data
    SELECT INTO cn_object       * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor  * FROM metabib.rec_descriptor   WHERE record = cn_object.record;

    -- Pre-generate this so we only calc it once
    IF user_object.dob IS NOT NULL THEN
        SELECT INTO user_age age(user_object.dob);
    END IF;

    -- Ditto
    SELECT INTO my_item_age age(coalesce(item_object.active_date, now()));

    -- Grab the closest set circ weight setting.
    SELECT INTO weights cw.*
      FROM config.weight_assoc wa
           JOIN config.circ_matrix_weights cw ON (cw.id = wa.circ_weights)
           JOIN actor.org_unit_ancestors_distance( context_ou ) d ON (wa.org_unit = d.id)
      WHERE active
      ORDER BY d.distance
      LIMIT 1;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.grp                 := 11.0;
        weights.org_unit            := 10.0;
        weights.org_lasso           := 10.0;
        weights.circ_modifier       := 5.0;
        weights.copy_location       := 5.0;
        weights.marc_type           := 4.0;
        weights.marc_form           := 3.0;
        weights.marc_bib_level      := 2.0;
        weights.marc_vr_format      := 2.0;
        weights.copy_circ_lib       := 8.0;
        weights.copy_circ_lasso     := 8.0;
        weights.copy_owning_lib     := 8.0;
        weights.copy_owning_lasso   := 8.0;
        weights.user_home_ou        := 8.0;
        weights.user_home_lasso     := 8.0;
        weights.ref_flag            := 1.0;
        weights.juvenile_flag       := 6.0;
        weights.is_renewal          := 7.0;
        weights.usr_age_lower_bound := 0.0;
        weights.usr_age_upper_bound := 0.0;
        weights.item_age            := 0.0;
    END IF;

    -- Determine the max (expected) depth (+1) of the org tree and max depth of the permisson tree
    -- If you break your org tree with funky parenting this may be wrong
    -- Note: This CTE is duplicated in the find_hold_matrix_matchpoint function, and it may be a good idea to split it off to a function
    -- We use one denominator for all tree-based checks for when permission groups and org units have the same weighting
    WITH all_distance(distance) AS (
            SELECT depth AS distance FROM actor.org_unit_type
        UNION
       	    SELECT distance AS distance FROM permission.grp_ancestors_distance((SELECT id FROM permission.grp_tree WHERE parent IS NULL))
	)
    SELECT INTO denominator MAX(distance) + 1 FROM all_distance;

    -- Loop over all the potential matchpoints
    FOR cur_matchpoint IN
        SELECT m.*
          FROM  config.circ_matrix_matchpoint m
                /*LEFT*/ JOIN permission.grp_ancestors_distance( user_object.profile ) upgad ON m.grp = upgad.id
                /*LEFT*/ JOIN actor.org_unit_ancestors_distance( context_ou ) ctoua ON m.org_unit = ctoua.id
                LEFT JOIN actor.org_unit_ancestors_distance( cn_object.owning_lib ) cnoua ON m.copy_owning_lib = cnoua.id
                LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.copy_circ_lib = iooua.id
                LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
                LEFT JOIN actor.org_lasso_map olm ON (olm.lasso = m.org_lasso AND olm.org_unit = context_ou)
                LEFT JOIN actor.org_lasso_map cclm ON (cclm.lasso = m.copy_circ_lasso AND cclm.org_unit = item_object.circ_lib)
                LEFT JOIN actor.org_lasso_map colm ON (colm.lasso = m.copy_owning_lasso AND colm.org_unit = cn_object.owning_lib)
                LEFT JOIN actor.org_lasso_map uhlm ON (uhlm.lasso = m.user_home_lasso AND uhlm.org_unit = user_object.home_ou)
          WHERE m.active
                -- Permission Groups
             -- AND (m.grp                      IS NULL OR upgad.id IS NOT NULL) -- Optional Permission Group?
                -- Org Units
             -- AND (m.org_unit                 IS NULL OR ctoua.id IS NOT NULL) -- Optional Org Unit?
                AND (m.org_lasso                IS NULL OR olm.id IS NOT NULL)
                AND (m.copy_owning_lib          IS NULL OR cnoua.id IS NOT NULL)
                AND (m.copy_owning_lasso        IS NULL OR colm.id IS NOT NULL)
                AND (m.copy_circ_lib            IS NULL OR iooua.id IS NOT NULL)
                AND (m.copy_circ_lasso          IS NULL OR cclm.id IS NOT NULL)
                AND (m.user_home_ou             IS NULL OR uhoua.id IS NOT NULL)
                AND (m.user_home_lasso          IS NULL OR uhlm.id IS NOT NULL)
                -- Circ Type
                AND (m.is_renewal               IS NULL OR m.is_renewal = renewal)
                -- Static User Checks
                AND (m.juvenile_flag            IS NULL OR m.juvenile_flag = user_object.juvenile)
                AND (m.usr_age_lower_bound      IS NULL OR (user_age IS NOT NULL AND m.usr_age_lower_bound < user_age))
                AND (m.usr_age_upper_bound      IS NULL OR (user_age IS NOT NULL AND m.usr_age_upper_bound > user_age))
                -- Static Item Checks
                AND (m.circ_modifier            IS NULL OR m.circ_modifier = item_object.circ_modifier)
                AND (m.copy_location            IS NULL OR m.copy_location = item_object.location)
                AND (m.marc_type                IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
                AND (m.marc_form                IS NULL OR m.marc_form = rec_descriptor.item_form)
                AND (m.marc_bib_level           IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
                AND (m.marc_vr_format           IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
                AND (m.ref_flag                 IS NULL OR m.ref_flag = item_object.ref)
                AND (m.item_age                 IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
          ORDER BY
                -- Permission Groups
                CASE WHEN upgad.distance        IS NOT NULL THEN 2^(2*weights.grp - (upgad.distance/denominator)) ELSE 0.0 END +
                -- Org Units
                CASE WHEN ctoua.distance        IS NOT NULL THEN 2^(2*weights.org_unit - (ctoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN olm.id                IS NOT NULL THEN weights.org_lasso ELSE 0.0 END +
                CASE WHEN cnoua.distance        IS NOT NULL THEN 2^(2*weights.copy_owning_lib - (cnoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN colm.id               IS NOT NULL THEN weights.copy_owning_lasso ELSE 0.0 END +
                CASE WHEN iooua.distance        IS NOT NULL THEN 2^(2*weights.copy_circ_lib - (iooua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN cclm.id               IS NOT NULL THEN weights.copy_circ_lasso ELSE 0.0 END +
                CASE WHEN uhoua.distance        IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN uhlm.id               IS NOT NULL THEN weights.user_home_lasso ELSE 0.0 END +
                -- Circ Type                    -- Note: 4^x is equiv to 2^(2*x)
                CASE WHEN m.is_renewal          IS NOT NULL THEN 4^weights.is_renewal ELSE 0.0 END +
                -- Static User Checks
                CASE WHEN m.juvenile_flag       IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
                CASE WHEN m.usr_age_lower_bound IS NOT NULL THEN 4^weights.usr_age_lower_bound ELSE 0.0 END +
                CASE WHEN m.usr_age_upper_bound IS NOT NULL THEN 4^weights.usr_age_upper_bound ELSE 0.0 END +
                -- Static Item Checks
                CASE WHEN m.circ_modifier       IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
                CASE WHEN m.copy_location       IS NOT NULL THEN 4^weights.copy_location ELSE 0.0 END +
                CASE WHEN m.marc_type           IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
                CASE WHEN m.marc_form           IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
                CASE WHEN m.marc_vr_format      IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
                CASE WHEN m.ref_flag            IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END +
                -- Item age has a slight adjustment to weight based on value.
                -- This should ensure that a shorter age limit comes first when all else is equal.
                -- NOTE: This assumes that intervals will normally be in days.
                CASE WHEN m.item_age            IS NOT NULL THEN 4^weights.item_age - 1 + 86400/EXTRACT(EPOCH FROM m.item_age) ELSE 0.0 END DESC,
                -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
                -- This prevents "we changed the table order by updating a rule, and we started getting different results"
                m.id LOOP

        -- Record the full matching row list
        row_list := row_list || cur_matchpoint.id;

        -- No matchpoint yet?
        IF matchpoint.id IS NULL THEN
            -- Take the entire matchpoint as a starting point
            matchpoint := cur_matchpoint;
            CONTINUE; -- No need to look at this row any more.
        END IF;

        -- Incomplete matchpoint?
        IF matchpoint.circulate IS NULL THEN
            matchpoint.circulate := cur_matchpoint.circulate;
        END IF;
        IF matchpoint.duration_rule IS NULL THEN
            matchpoint.duration_rule := cur_matchpoint.duration_rule;
        END IF;
        IF matchpoint.recurring_fine_rule IS NULL THEN
            matchpoint.recurring_fine_rule := cur_matchpoint.recurring_fine_rule;
        END IF;
        IF matchpoint.max_fine_rule IS NULL THEN
            matchpoint.max_fine_rule := cur_matchpoint.max_fine_rule;
        END IF;
        IF matchpoint.hard_due_date IS NULL THEN
            matchpoint.hard_due_date := cur_matchpoint.hard_due_date;
        END IF;
        IF matchpoint.total_copy_hold_ratio IS NULL THEN
            matchpoint.total_copy_hold_ratio := cur_matchpoint.total_copy_hold_ratio;
        END IF;
        IF matchpoint.available_copy_hold_ratio IS NULL THEN
            matchpoint.available_copy_hold_ratio := cur_matchpoint.available_copy_hold_ratio;
        END IF;
        IF matchpoint.renewals IS NULL THEN
            matchpoint.renewals := cur_matchpoint.renewals;
        END IF;
        IF matchpoint.grace_period IS NULL THEN
            matchpoint.grace_period := cur_matchpoint.grace_period;
        END IF;
    END LOOP;

    -- Check required fields
    IF matchpoint.circulate             IS NOT NULL AND
       matchpoint.duration_rule         IS NOT NULL AND
       matchpoint.recurring_fine_rule   IS NOT NULL AND
       matchpoint.max_fine_rule         IS NOT NULL THEN
        -- All there? We have a completed match.
        result.success := true;
    END IF;

    -- Include the assembled matchpoint, even if it isn't complete
    result.matchpoint := matchpoint;

    -- Include (for debugging) the full list of matching rows
    result.buildrows := row_list;

    -- Hand the result back to caller
    RETURN result;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint(pickup_ou integer, request_ou integer, match_item bigint, match_user integer, match_requestor integer)
  RETURNS integer AS
$func$
DECLARE
    requestor_object    actor.usr%ROWTYPE;
    user_object         actor.usr%ROWTYPE;
    item_object         asset.copy%ROWTYPE;
    item_cn_object      asset.call_number%ROWTYPE;
    my_item_age         INTERVAL;
    rec_descriptor      metabib.rec_descriptor%ROWTYPE;
    matchpoint          config.hold_matrix_matchpoint%ROWTYPE;
    weights             config.hold_matrix_weights%ROWTYPE;
    denominator         NUMERIC(6,2);
    v_pickup_ou         ALIAS FOR pickup_ou;
    v_request_ou         ALIAS FOR request_ou;
BEGIN
    SELECT INTO user_object         * FROM actor.usr                WHERE id = match_user;
    SELECT INTO requestor_object    * FROM actor.usr                WHERE id = match_requestor;
    SELECT INTO item_object         * FROM asset.copy               WHERE id = match_item;
    SELECT INTO item_cn_object      * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor      * FROM metabib.rec_descriptor   WHERE record = item_cn_object.record;

    SELECT INTO my_item_age age(coalesce(item_object.active_date, now()));

    -- The item's owner should probably be the one determining if the item is holdable
    -- How to decide that is debatable. Decided to default to the circ library (where the item lives)
    -- This flag will allow for setting it to the owning library (where the call number "lives")
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.weight_owner_not_circ' AND enabled;

    -- Grab the closest set circ weight setting.
    IF NOT FOUND THEN
        -- Default to circ library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    ELSE
        -- Flag is set, use owning library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    END IF;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.user_home_ou    := 5.0;
        weights.request_ou      := 5.0;
        weights.pickup_ou       := 5.0;
        weights.item_owning_ou  := 5.0;
        weights.item_circ_ou    := 5.0;
        weights.user_home_lasso := 5.0;
        weights.request_lasso   := 5.0;
        weights.pickup_lasso    := 5.0;
        weights.item_owning_lasso := 5.0;
        weights.item_circ_lasso := 5.0;
        weights.usr_grp         := 7.0;
        weights.requestor_grp   := 8.0;
        weights.circ_modifier   := 4.0;
        weights.copy_location   := 4.0;
        weights.marc_type       := 3.0;
        weights.marc_form       := 2.0;
        weights.marc_bib_level  := 1.0;
        weights.marc_vr_format  := 1.0;
        weights.juvenile_flag   := 4.0;
        weights.ref_flag        := 0.0;
        weights.item_age        := 0.0;
    END IF;

    -- Determine the max (expected) depth (+1) of the org tree and max depth of the permisson tree
    -- If you break your org tree with funky parenting this may be wrong
    -- Note: This CTE is duplicated in the find_circ_matrix_matchpoint function, and it may be a good idea to split it off to a function
    -- We use one denominator for all tree-based checks for when permission groups and org units have the same weighting
    WITH all_distance(distance) AS (
            SELECT depth AS distance FROM actor.org_unit_type
        UNION
            SELECT distance AS distance FROM permission.grp_ancestors_distance((SELECT id FROM permission.grp_tree WHERE parent IS NULL))
	)
    SELECT INTO denominator MAX(distance) + 1 FROM all_distance;

    -- To ATTEMPT to make this work like it used to, make it reverse the user/requestor profile ids.
    -- This may be better implemented as part of the upgrade script?
    -- Set usr_grp = requestor_grp, requestor_grp = 1 or something when this flag is already set
    -- Then remove this flag, of course.
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.usr_not_requestor' AND enabled;

    IF FOUND THEN
        -- Note: This, to me, is REALLY hacky. I put it in anyway.
        -- If you can't tell, this is a single call swap on two variables.
        SELECT INTO user_object.profile, requestor_object.profile
                    requestor_object.profile, user_object.profile;
    END IF;

    -- Select the winning matchpoint into the matchpoint variable for returning
    SELECT INTO matchpoint m.*
      FROM  config.hold_matrix_matchpoint m
            /*LEFT*/ JOIN permission.grp_ancestors_distance( requestor_object.profile ) rpgad ON m.requestor_grp = rpgad.id
            LEFT JOIN permission.grp_ancestors_distance( user_object.profile ) upgad ON m.usr_grp = upgad.id
            LEFT JOIN actor.org_unit_ancestors_distance( v_pickup_ou ) puoua ON m.pickup_ou = puoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( v_request_ou ) rqoua ON m.request_ou = rqoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) cnoua ON m.item_owning_ou = cnoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.item_circ_ou = iooua.id
            LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
            LEFT JOIN actor.org_lasso_map puol ON (puol.lasso = m.pickup_lasso AND puol.org_unit = v_pickup_ou)
            LEFT JOIN actor.org_lasso_map rqol ON (rqol.lasso = m.request_lasso AND rqol.org_unit = v_request_ou)
            LEFT JOIN actor.org_lasso_map cnol ON (cnol.lasso = m.item_owning_lasso AND cnol.org_unit = item_cn_object.owning_lib)
            LEFT JOIN actor.org_lasso_map iool ON (iool.lasso = m.item_circ_lasso AND iool.org_unit = item_object.circ_lib)
            LEFT JOIN actor.org_lasso_map uhol ON (uhol.lasso = m.user_home_lasso AND uhol.org_unit = user_object.home_ou)
      WHERE m.active
            -- Permission Groups
         -- AND (m.requestor_grp        IS NULL OR upgad.id IS NOT NULL) -- Optional Requestor Group?
            AND (m.usr_grp              IS NULL OR upgad.id IS NOT NULL)
            -- Org Units
            AND (m.pickup_ou            IS NULL OR (puoua.id IS NOT NULL AND (puoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.request_ou           IS NULL OR (rqoua.id IS NOT NULL AND (rqoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_owning_ou       IS NULL OR (cnoua.id IS NOT NULL AND (cnoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_circ_ou         IS NULL OR (iooua.id IS NOT NULL AND (iooua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.user_home_ou         IS NULL OR (uhoua.id IS NOT NULL AND (uhoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.pickup_lasso         IS NULL OR puol.id IS NOT NULL)
            AND (m.request_lasso        IS NULL OR rqol.id IS NOT NULL)
            AND (m.item_owning_lasso    IS NULL OR cnol.id IS NOT NULL)
            AND (m.item_circ_lasso      IS NULL OR iool.id IS NOT NULL)
            AND (m.user_home_lasso      IS NULL OR uhol.id IS NOT NULL)
            -- Static User Checks
            AND (m.juvenile_flag        IS NULL OR m.juvenile_flag = user_object.juvenile)
            -- Static Item Checks
            AND (m.circ_modifier        IS NULL OR m.circ_modifier = item_object.circ_modifier)
            AND (m.copy_location        IS NULL OR m.copy_location = item_object.location)
            AND (m.marc_type            IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
            AND (m.marc_form            IS NULL OR m.marc_form = rec_descriptor.item_form)
            AND (m.marc_bib_level       IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
            AND (m.marc_vr_format       IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
            AND (m.ref_flag             IS NULL OR m.ref_flag = item_object.ref)
            AND (m.item_age             IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
      ORDER BY
            -- Permission Groups
            CASE WHEN rpgad.distance    IS NOT NULL THEN 2^(2*weights.requestor_grp - (rpgad.distance/denominator)) ELSE 0.0 END +
            CASE WHEN upgad.distance    IS NOT NULL THEN 2^(2*weights.usr_grp - (upgad.distance/denominator)) ELSE 0.0 END +
            -- Org Units
            CASE WHEN puoua.distance    IS NOT NULL THEN 2^(2*weights.pickup_ou - (puoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN puol.id           IS NOT NULL THEN weights.pickup_lasso ELSE 0.0 END +
            CASE WHEN rqoua.distance    IS NOT NULL THEN 2^(2*weights.request_ou - (rqoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN rqol.id           IS NOT NULL THEN weights.request_lasso ELSE 0.0 END +
            CASE WHEN cnoua.distance    IS NOT NULL THEN 2^(2*weights.item_owning_ou - (cnoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN cnol.id           IS NOT NULL THEN weights.item_owning_lasso ELSE 0.0 END +
            CASE WHEN iooua.distance    IS NOT NULL THEN 2^(2*weights.item_circ_ou - (iooua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN iool.id           IS NOT NULL THEN weights.item_circ_lasso ELSE 0.0 END +
            CASE WHEN uhoua.distance    IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN uhol.id           IS NOT NULL THEN weights.user_home_lasso ELSE 0.0 END +
            -- Static User Checks       -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.juvenile_flag   IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier   IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
            CASE WHEN m.copy_location   IS NOT NULL THEN 4^weights.copy_location ELSE 0.0 END +
            CASE WHEN m.marc_type       IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
            CASE WHEN m.marc_form       IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
            CASE WHEN m.marc_vr_format  IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
            CASE WHEN m.ref_flag        IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END +
            -- Item age has a slight adjustment to weight based on value.
            -- This should ensure that a shorter age limit comes first when all else is equal.
            -- NOTE: This assumes that intervals will normally be in days.
            CASE WHEN m.item_age            IS NOT NULL THEN 4^weights.item_age - 86400/EXTRACT(EPOCH FROM m.item_age) ELSE 0.0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return just the ID for now
    RETURN matchpoint.id;
END;
$func$ LANGUAGE 'plpgsql';



SELECT evergreen.upgrade_deps_block_check('1515', :eg_version);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.checkin.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.checkin.batch_notify',
        'Notification of a group of check ins',
        'ath',
        'description'
    ),
    FALSE
), (
    'circ.items_out.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.items_out.batch_notify',
        'Notification of a group of items out',
        'ath',
        'description'
    ),
    FALSE
), (
    'circ.renew.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.renew.batch_notify',
        'Notification of a group of renewals',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    usr_field,
    opt_in_setting,
    group_field,
    template
) VALUES (
    TRUE,
    1,
    'Email Check In Receipt',
    'circ.checkin.batch_notify',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.checkin_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Check In Receipt
Auto-Submitted: auto-generated

You checked in the following items:

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Barcode: [% circ.target_copy.barcode %]
    Library: [% circ.checkin_lib.name %]

[% END %]
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.call_number'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'checkin_lib'
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    usr_field,
    opt_in_setting,
    group_field,
    template
) VALUES (
    TRUE,
    1,
    'Email Items Out Receipt',
    'circ.items_out.batch_notify',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.circ_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Items Out Receipt
Auto-Submitted: auto-generated

You have the following items:

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Barcode: [% circ.target_copy.barcode %]
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Library: [% circ.circ_lib.name %]

[% END %]
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.call_number'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'circ_lib'
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    usr_field,
    opt_in_setting,
    group_field,
    template
) VALUES (
    TRUE,
    1,
    'Email Renewal Receipt',
    'circ.renew.batch_notify',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.circ_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Renewal Receipt
Auto-Submitted: auto-generated

You renewed the following items:

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Barcode: [% circ.target_copy.barcode %]
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Library: [% circ.circ_lib.name %]

[% END %]
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.call_number'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'circ_lib'
);


SELECT evergreen.upgrade_deps_block_check('1516', :eg_version);

CREATE OR REPLACE FUNCTION actor.user_ingest_name_keywords()
    RETURNS TRIGGER AS $func$
BEGIN
    NEW.name_kw_tsvector := TO_TSVECTOR(
        COALESCE(NEW.prefix, '')                || ' ' ||
        COALESCE(NEW.first_given_name, '')      || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.first_given_name), '') || ' ' ||
        COALESCE(NEW.second_given_name, '')     || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.second_given_name), '') || ' ' ||
        COALESCE(NEW.family_name, '')           || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.family_name), '') || ' ' ||
        COALESCE(NEW.suffix, '')                || ' ' ||
        COALESCE(NEW.pref_prefix, '')            || ' ' ||
        COALESCE(NEW.pref_first_given_name, '')  || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_first_given_name), '') || ' ' ||
        COALESCE(NEW.pref_second_given_name, '') || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_second_given_name), '') || ' ' ||
        COALESCE(NEW.pref_family_name, '')       || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.pref_family_name), '') || ' ' ||
        COALESCE(NEW.pref_suffix, '')            || ' ' ||
        COALESCE(NEW.name_keywords, '')          || ' ' ||
        COALESCE(NEW.guardian, '')               || ' ' ||
        COALESCE(evergreen.unaccent_and_squash(NEW.guardian), '')
    );
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


-- to trigger user_ingest_name_keywords_tgr
-- UPDATE actor.usr SET id = id WHERE NOT DELETED;

\qecho ''
\qecho '-----'
\qecho 'To update the patron search keyword index to include patron/guardian '
\qecho 'data for existing patrons, update non-deleted actor.usr rows'
\qecho 'similar to the following, with the caveat that updating larger data'
\qecho 'sets should probably be performed in batches.'
\qecho ''
\qecho 'UPDATE actor.usr SET id = id WHERE NOT deleted AND guardian IS NOT NULL;'
\qecho '-----'
\qecho ''


-- Add Stackmap library settings

SELECT evergreen.upgrade_deps_block_check('1517', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.stackmap_enable',
    'opac',
    oils_i18n_gettext('opac.stackmap_enable',
    'Stackmap: Enable',
    'coust', 'label'),
    oils_i18n_gettext('opac.stackmap_enable',
    'Enable Stackmap in the OPAC. Default is false.',
    'coust', 'description'),
    'bool'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.stackmap_identifier',
    'opac',
    oils_i18n_gettext('opac.stackmap_identifier',
    'Stackmap: Identifier',
    'coust', 'label'),
    oils_i18n_gettext('opac.stackmap_identifier',
    'Account code provided by Stackmap. (Example: pines-evergreen)',
    'coust', 'description'),
    'string'
);

SELECT evergreen.upgrade_deps_block_check('1518', :eg_version);

ALTER FUNCTION actor.org_unit_ancestors(INT) STABLE;
ALTER FUNCTION actor.org_unit_descendants(INT) STABLE;
ALTER FUNCTION actor.org_unit_descendants(INT,INT) STABLE;

SELECT evergreen.upgrade_deps_block_check('1519', :eg_version);

CREATE OR REPLACE FUNCTION acq.create_acq_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$CREATE SEQUENCE acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_pkey_seq$$);
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE acq.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            LIKE $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE FUNCTION acq.audit_$$ || quote_ident(sch || $$_$$ || tbl || $$_func$$) || $$ ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$
                SELECT	nextval($$ || quote_literal($$acq.$$ || sch || $$_$$ || tbl || $$_pkey_seq$$) || $$),
                    now(),
                    SUBSTR(TG_OP,1,1),
                    OLD.*;
            RETURN NULL;
        END;
        $func$ LANGUAGE 'plpgsql';
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER audit_$$ || quote_ident(sch || $$_$$ || tbl || $$_update_trigger$$) || $$
            AFTER UPDATE OR DELETE ON $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$ FOR EACH ROW
            EXECUTE PROCEDURE acq.audit_$$ || quote_ident(sch || $$_$$ || tbl || $$_func$$) || $$ ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE VIEW acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_lifecycle$$) || $$ AS
            SELECT	-1, now() as audit_time, '-' as audit_action, *
              FROM	$$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT	*
              FROM	acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$CREATE SEQUENCE auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_pkey_seq$$);
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$ (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            audit_user  INT,
            audit_ws    INT,
            LIKE $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
DECLARE
    column_list TEXT[];
BEGIN
    SELECT INTO column_list array_agg(a.attname)
        FROM pg_catalog.pg_attribute a
            JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE relkind = 'r' AND n.nspname = sch AND c.relname = tbl AND a.attnum > 0 AND NOT a.attisdropped;

    EXECUTE $$
        CREATE OR REPLACE FUNCTION auditor.$$ || quote_ident($$audit_$$ || sch || $$_$$ || tbl || $$_func$$) || $$ ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$ ( audit_id, audit_time, audit_action, audit_user, audit_ws, $$
            || array_to_string(column_list, ', ') || $$ )
                SELECT  nextval($$ || quote_literal($$auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq$$) || $$),
                    now(),
                    SUBSTR(TG_OP,1,1),
                    eg_user,
                    eg_ws,
                    OLD.$$ || array_to_string(column_list, ', OLD.') || $$
                FROM auditor.get_audit_info();
            RETURN NULL;
        END;
        $func$ LANGUAGE 'plpgsql';
    $$;
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER $$ || quote_ident($$audit_$$ || sch || $$_$$ || tbl || $$_update_trigger$$) || $$
            AFTER UPDATE OR DELETE ON $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$ FOR EACH ROW
            EXECUTE PROCEDURE auditor.$$ || quote_ident($$audit_$$ || sch || $$_$$ || tbl || $$_func$$) || $$ ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
DECLARE
    column_list TEXT[];
BEGIN
    SELECT INTO column_list array_agg(a.attname)
        FROM pg_catalog.pg_attribute a
            JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE relkind = 'r' AND n.nspname = sch AND c.relname = tbl AND a.attnum > 0 AND NOT a.attisdropped;

    EXECUTE $$
        CREATE VIEW auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_lifecycle$$) || $$ AS
            SELECT -1 AS audit_id,
                   now() AS audit_time,
                   '-' AS audit_action,
                   -1 AS audit_user,
                   -1 AS audit_ws,
                   $$ || array_to_string(column_list, ', ') || $$
              FROM $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$
                UNION ALL
            SELECT audit_id, audit_time, audit_action, audit_user, audit_ws,
            $$ || array_to_string(column_list, ', ') || $$
              FROM auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$;
    $$;
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    IF NEW.label_class IS NULL THEN
            NEW.label_class := COALESCE(
            (   
                SELECT substring(value from E'\\d+')::integer
                FROM actor.org_unit_ancestor_setting('cat.default_classification_scheme', NEW.owning_lib)
            ), 1
        );
    END IF;

    EXECUTE FORMAT('SELECT %s(%L)', acnc.normalizer::REGPROC, NEW.label)
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;
    NEW.label_sortkey = sortkey;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS public.extract_marc_field(TEXT, BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.extract_marc_field(TEXT, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION evergreen.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    query := FORMAT($q$
        SELECT  regexp_replace(
                    oils_xpath_string(
                        %L,
                        marc,
                        ' '
                    ),
                    %L,
                    '',
                    'g')
          FROM %s
          WHERE id = %L
    $q$, $3, $4, $1::REGCLASS, $2);

    EXECUTE query INTO output;

    -- RAISE NOTICE 'query: %, output; %', query, output;

    RETURN output;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
    SELECT extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL IMMUTABLE;

DROP FUNCTION IF EXISTS unapi.memoize(TEXT, BIGINT, TEXT, TEXT, TEXT[], TEXT, INT, HSTORE, HSTORE, BOOL);

CREATE OR REPLACE FUNCTION actor.usr_merge_rows( table_name TEXT, col_name TEXT, src_usr INT, dest_usr INT ) RETURNS VOID AS $$
DECLARE
    sel TEXT;
    upd TEXT;
    del TEXT;
    cur_row RECORD;
BEGIN
    sel := FORMAT('SELECT id::BIGINT FROM %s WHERE %I = $1', table_name::REGCLASS, col_name);
    upd := FORMAT('UPDATE %s SET %I = $1 WHERE id = $2', table_name::REGCLASS, col_name);
    del := FORMAT('DELETE FROM %s WHERE id = $1', table_name::REGCLASS);
    FOR cur_row IN EXECUTE sel USING src_usr LOOP
        BEGIN
            EXECUTE upd USING dest_usr, cur_row.id;
        EXCEPTION WHEN unique_violation THEN
            EXECUTE del USING cur_row.id;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS evergreen.change_db_setting(TEXT, TEXT[]);

ALTER TABLE config.metabib_class ADD CHECK (name ~ '^\w+$');

CREATE OR REPLACE FUNCTION search.symspell_lookup (
    raw_input       TEXT,
    search_class    TEXT,
    verbosity       INT DEFAULT NULL,
    xfer_case       BOOL DEFAULT NULL,
    count_threshold INT DEFAULT NULL,
    soundex_weight  INT DEFAULT NULL,
    pg_trgm_weight  INT DEFAULT NULL,
    kbdist_weight   INT DEFAULT NULL
) RETURNS SETOF search.symspell_lookup_output AS $F$
DECLARE
    prefix_length INT;
    maxED         INT;
    good_suggs  HSTORE;
    word_list   TEXT[];
    edit_list   TEXT[] := '{}';
    seen_list   TEXT[] := '{}';
    output      search.symspell_lookup_output;
    output_list search.symspell_lookup_output[];
    entry       RECORD;
    entry_key   TEXT;
    prefix_key  TEXT;
    sugg        TEXT;
    input       TEXT;
    word        TEXT;
    w_pos       INT := -1;
    smallest_ed INT := -1;
    global_ed   INT;
    c_symspell_suggestion_verbosity INT;
    c_min_suggestion_use_threshold  INT;
    c_soundex_weight                INT;
    c_pg_trgm_weight                INT;
    c_keyboard_distance_weight      INT;
    c_symspell_transfer_case        BOOL;
BEGIN

    SELECT  cmc.min_suggestion_use_threshold,
            cmc.soundex_weight,
            cmc.pg_trgm_weight,
            cmc.keyboard_distance_weight,
            cmc.symspell_transfer_case,
            cmc.symspell_suggestion_verbosity
      INTO  c_min_suggestion_use_threshold,
            c_soundex_weight,
            c_pg_trgm_weight,
            c_keyboard_distance_weight,
            c_symspell_transfer_case,
            c_symspell_suggestion_verbosity
      FROM  config.metabib_class cmc
      WHERE cmc.name = search_class;

    IF NOT FOUND THEN RETURN; END IF; -- If the requested search class doesn't exist, we leave.

    c_min_suggestion_use_threshold := COALESCE(count_threshold,c_min_suggestion_use_threshold);
    c_symspell_transfer_case := COALESCE(xfer_case,c_symspell_transfer_case);
    c_symspell_suggestion_verbosity := COALESCE(verbosity,c_symspell_suggestion_verbosity);
    c_soundex_weight := COALESCE(soundex_weight,c_soundex_weight);
    c_pg_trgm_weight := COALESCE(pg_trgm_weight,c_pg_trgm_weight);
    c_keyboard_distance_weight := COALESCE(kbdist_weight,c_keyboard_distance_weight);

    SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
    prefix_length := COALESCE(prefix_length, 6);

    SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
    maxED := COALESCE(maxED, 3);

    -- XXX This should get some more thought ... maybe search_normalize?
    word_list := ARRAY_AGG(x.word) FROM search.query_parse_positions(raw_input) x;

    -- Common case exact match test for preformance
    IF c_symspell_suggestion_verbosity = 0 AND CARDINALITY(word_list) = 1 AND CHARACTER_LENGTH(word_list[1]) <= prefix_length THEN
        EXECUTE
          'SELECT  '||search_class||'_suggestions AS suggestions,
                   '||search_class||'_count AS count,
                   prefix_key
             FROM  search.symspell_dictionary
             WHERE prefix_key = $1
                   AND '||search_class||'_count >= $2 
                   AND '||search_class||'_suggestions @> ARRAY[$1]' 
          INTO entry USING evergreen.lowercase(word_list[1]), c_min_suggestion_use_threshold;
        IF entry.prefix_key IS NOT NULL THEN
            output.lev_distance := 0; -- definitionally
            output.prefix_key := entry.prefix_key;
            output.prefix_key_count := entry.count;
            output.suggestion_count := entry.count;
            output.input := word_list[1];
            IF c_symspell_transfer_case THEN
                output.suggestion := search.symspell_transfer_casing(output.input, entry.prefix_key);
            ELSE
                output.suggestion := entry.prefix_key;
            END IF;
            output.norm_input := entry.prefix_key;
            output.qwerty_kb_match := 1;
            output.pg_trgm_sim := 1;
            output.soundex_sim := 1;
            RETURN NEXT output;
            RETURN;
        END IF;
    END IF;

    <<word_loop>>
    FOREACH word IN ARRAY word_list LOOP
        w_pos := w_pos + 1;
        input := evergreen.lowercase(word);

        IF CHARACTER_LENGTH(input) > prefix_length THEN
            prefix_key := SUBSTRING(input FROM 1 FOR prefix_length);
            edit_list := ARRAY[input,prefix_key] || search.symspell_generate_edits(prefix_key, 1, maxED);
        ELSE
            edit_list := input || search.symspell_generate_edits(input, 1, maxED);
        END IF;

        SELECT ARRAY_AGG(x ORDER BY CHARACTER_LENGTH(x) DESC) INTO edit_list FROM UNNEST(edit_list) x;

        output_list := '{}';
        seen_list := '{}';
        global_ed := NULL;

        <<entry_key_loop>>
        FOREACH entry_key IN ARRAY edit_list LOOP
            smallest_ed := -1;
            IF global_ed IS NOT NULL THEN
                smallest_ed := global_ed;
            END IF;
            FOR entry IN EXECUTE
                'SELECT  '||search_class||'_suggestions AS suggestions,
                         '||search_class||'_count AS count,
                         prefix_key
                   FROM  search.symspell_dictionary
                   WHERE prefix_key = $1
                         AND '||search_class||'_suggestions IS NOT NULL' 
                USING entry_key
            LOOP

                SELECT  HSTORE(
                            ARRAY_AGG(
                                ARRAY[s, evergreen.levenshtein_damerau_edistance(input,s,maxED)::TEXT]
                                    ORDER BY evergreen.levenshtein_damerau_edistance(input,s,maxED) ASC
                            )
                        )
                  INTO  good_suggs
                  FROM  UNNEST(entry.suggestions) s
                  WHERE (ABS(CHARACTER_LENGTH(s) - CHARACTER_LENGTH(input)) <= maxEd
                        AND evergreen.levenshtein_damerau_edistance(input,s,maxED) BETWEEN 0 AND maxED)
                        AND NOT seen_list @> ARRAY[s];

                CONTINUE WHEN good_suggs IS NULL;

                FOR sugg, output.suggestion_count IN EXECUTE
                    'SELECT  prefix_key, '||search_class||'_count
                       FROM  search.symspell_dictionary
                       WHERE prefix_key = ANY ($1)
                             AND '||search_class||'_count >= $2'
                    USING AKEYS(good_suggs), c_min_suggestion_use_threshold
                LOOP

                    IF NOT seen_list @> ARRAY[sugg] THEN
                        output.lev_distance := good_suggs->sugg;
                        seen_list := seen_list || sugg;

                        -- Track the smallest edit distance among suggestions from this prefix key.
                        IF smallest_ed = -1 OR output.lev_distance < smallest_ed THEN
                            smallest_ed := output.lev_distance;
                        END IF;

                        -- Track the smallest edit distance for all prefix keys for this word.
                        IF global_ed IS NULL OR smallest_ed < global_ed THEN
                            global_ed = smallest_ed;
                        END IF;

                        -- Only proceed if the edit distance is <= the max for the dictionary.
                        IF output.lev_distance <= maxED THEN
                            IF output.lev_distance > global_ed AND c_symspell_suggestion_verbosity <= 1 THEN
                                -- Lev distance is our main similarity measure. While
                                -- trgm or soundex similarity could be the main filter,
                                -- Lev is both language agnostic and faster.
                                --
                                -- Here we will skip suggestions that have a longer edit distance
                                -- than the shortest we've already found. This is simply an
                                -- optimization that allows us to avoid further processing
                                -- of this entry. It would be filtered out later.

                                CONTINUE;
                            END IF;

                            -- If we have an exact match on the suggestion key we can also avoid
                            -- some function calls.
                            IF output.lev_distance = 0 THEN
                                output.qwerty_kb_match := 1;
                                output.pg_trgm_sim := 1;
                                output.soundex_sim := 1;
                            ELSE
                                output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(input, sugg);
                                output.pg_trgm_sim := similarity(input, sugg);
                                output.soundex_sim := difference(input, sugg) / 4.0;
                            END IF;

                            -- Fill in some fields
                            IF c_symspell_transfer_case THEN
                                output.suggestion := search.symspell_transfer_casing(word, sugg);
                            ELSE
                                output.suggestion := sugg;
                            END IF;
                            output.prefix_key := entry.prefix_key;
                            output.prefix_key_count := entry.count;
                            output.input := word;
                            output.norm_input := input;
                            output.word_pos := w_pos;

                            -- We can't "cache" a set of generated records directly, so
                            -- here we build up an array of search.symspell_lookup_output
                            -- records that we can revivicate later as a table using UNNEST().
                            output_list := output_list || output;

                            EXIT entry_key_loop WHEN smallest_ed = 0 AND c_symspell_suggestion_verbosity = 0; -- exact match early exit
                            CONTINUE entry_key_loop WHEN smallest_ed = 0 AND c_symspell_suggestion_verbosity = 1; -- exact match early jump to the next key
                        END IF; -- maxED test
                    END IF; -- suggestion not seen test
                END LOOP; -- loop over suggestions
            END LOOP; -- loop over entries
        END LOOP; -- loop over entry_keys

        -- Now we're done examining this word
        IF c_symspell_suggestion_verbosity = 0 THEN
            -- Return the "best" suggestion from the smallest edit
            -- distance group.  We define best based on the weighting
            -- of the non-lev similarity measures and use the suggestion
            -- use count to break ties.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC
                        LIMIT 1;
        ELSIF c_symspell_suggestion_verbosity = 1 THEN
            -- Return all suggestions from the smallest
            -- edit distance group.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list) WHERE lev_distance = smallest_ed
                    ORDER BY (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        ELSIF c_symspell_suggestion_verbosity = 2 THEN
            -- Return everything we find, along with relevant stats
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        ELSIF c_symspell_suggestion_verbosity = 3 THEN
            -- Return everything we find from the two smallest edit distance groups
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        ELSIF c_symspell_suggestion_verbosity = 4 THEN
            -- Return everything we find from the two smallest edit distance groups that are NOT 0 distance
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) WHERE lev_distance > 0 ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * c_soundex_weight)
                            + (pg_trgm_sim * c_pg_trgm_weight)
                            + (qwerty_kb_match * c_keyboard_distance_weight) DESC,
                        suggestion_count DESC;
        END IF;
    END LOOP; -- loop over words
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_suggest (
    raw_input       TEXT,
    search_class    TEXT,
    search_fields   TEXT[] DEFAULT '{}',
    max_ed          INT DEFAULT NULL,      -- per word, on average, between norm input and suggestion
    verbosity       INT DEFAULT NULL,      -- 0=Best only; 1=
    skip_correct    BOOL DEFAULT NULL,  -- only suggest replacement words for misspellings?
    max_word_opts   INT DEFAULT NULL,   -- 0 means all combinations, probably want to restrict?
    count_threshold INT DEFAULT NULL    -- min count of records using the terms
) RETURNS SETOF search.symspell_lookup_output AS $F$
DECLARE
    sugg_set         search.symspell_lookup_output[];
    parsed_query_set search.query_parse_position[];
    entry            RECORD;
    auth_entry       RECORD;
    norm_count       RECORD;
    current_sugg     RECORD;
    auth_sugg        RECORD;
    norm_test        TEXT;
    norm_input       TEXT;
    norm_sugg        TEXT;
    query_part       TEXT := '';
    output           search.symspell_lookup_output;
    c_skip_correct                  BOOL;
    c_variant_authority_suggestion  BOOL;
    c_symspell_transfer_case        BOOL;
    c_authority_class_restrict      BOOL;
    c_min_suggestion_use_threshold  INT;
    c_soundex_weight                INT;
    c_pg_trgm_weight                INT;
    c_keyboard_distance_weight      INT;
    c_suggestion_word_option_count  INT;
    c_symspell_suggestion_verbosity INT;
    c_max_phrase_edit_distance      INT;
BEGIN

    -- Gather settings
    SELECT  cmc.min_suggestion_use_threshold,
            cmc.soundex_weight,
            cmc.pg_trgm_weight,
            cmc.keyboard_distance_weight,
            cmc.suggestion_word_option_count,
            cmc.symspell_suggestion_verbosity,
            cmc.symspell_skip_correct,
            cmc.symspell_transfer_case,
            cmc.max_phrase_edit_distance,
            cmc.variant_authority_suggestion,
            cmc.restrict
      INTO  c_min_suggestion_use_threshold,
            c_soundex_weight,
            c_pg_trgm_weight,
            c_keyboard_distance_weight,
            c_suggestion_word_option_count,
            c_symspell_suggestion_verbosity,
            c_skip_correct,
            c_symspell_transfer_case,
            c_max_phrase_edit_distance,
            c_variant_authority_suggestion,
            c_authority_class_restrict
      FROM  config.metabib_class cmc
      WHERE cmc.name = search_class;

    IF NOT FOUND THEN RETURN; END IF; -- If the requested search class doesn't exist, we leave.

    -- Set up variables to use at run time based on params and settings
    c_min_suggestion_use_threshold := COALESCE(count_threshold,c_min_suggestion_use_threshold);
    c_max_phrase_edit_distance := COALESCE(max_ed,c_max_phrase_edit_distance);
    c_symspell_suggestion_verbosity := COALESCE(verbosity,c_symspell_suggestion_verbosity);
    c_suggestion_word_option_count := COALESCE(max_word_opts,c_suggestion_word_option_count);
    c_skip_correct := COALESCE(skip_correct,c_skip_correct);

    SELECT  ARRAY_AGG(
                x ORDER BY  x.word_pos,
                            x.lev_distance,
                            (x.soundex_sim * c_soundex_weight)
                                + (x.pg_trgm_sim * c_pg_trgm_weight)
                                + (x.qwerty_kb_match * c_keyboard_distance_weight) DESC,
                            x.suggestion_count DESC
            ) INTO sugg_set
      FROM  search.symspell_lookup(
                raw_input,
                search_class,
                c_symspell_suggestion_verbosity,
                c_symspell_transfer_case,
                c_min_suggestion_use_threshold,
                c_soundex_weight,
                c_pg_trgm_weight,
                c_keyboard_distance_weight
            ) x
      WHERE x.lev_distance <= c_max_phrase_edit_distance;

    SELECT ARRAY_AGG(x) INTO parsed_query_set FROM search.query_parse_positions(raw_input) x;

    IF search_fields IS NOT NULL AND CARDINALITY(search_fields) > 0 THEN
        SELECT STRING_AGG(id::TEXT,',') INTO query_part FROM config.metabib_field WHERE name = ANY (search_fields);
        IF CHARACTER_LENGTH(query_part) > 0 THEN query_part := 'AND field IN ('||query_part||')'; END IF;
    END IF;

    SELECT STRING_AGG(word,' ') INTO norm_input FROM search.query_parse_positions(evergreen.lowercase(raw_input)) WHERE NOT negated;
    EXECUTE 'SELECT  COUNT(DISTINCT source) AS recs
               FROM  metabib.' || search_class || '_field_entry
               WHERE index_vector @@ plainto_tsquery($$simple$$,$1)' || query_part
            INTO norm_count USING norm_input;

    SELECT STRING_AGG(word,' ') INTO norm_test FROM UNNEST(parsed_query_set);
    FOR current_sugg IN
        SELECT  *
          FROM  search.symspell_generate_combined_suggestions(
                    sugg_set,
                    parsed_query_set,
                    c_skip_correct,
                    c_suggestion_word_option_count
                ) x
    LOOP
        EXECUTE 'SELECT  COUNT(DISTINCT source) AS recs
                   FROM  metabib.' || search_class || '_field_entry
                   WHERE index_vector @@ to_tsquery($$simple$$,$1)' || query_part
                INTO entry USING current_sugg.test;
        SELECT STRING_AGG(word,' ') INTO norm_sugg FROM search.query_parse_positions(current_sugg.suggestion);
        IF entry.recs >= c_min_suggestion_use_threshold AND (norm_count.recs = 0 OR norm_sugg <> norm_input) THEN

            output.input := raw_input;
            output.norm_input := norm_input;
            output.suggestion := current_sugg.suggestion;
            output.suggestion_count := entry.recs;
            output.prefix_key := NULL;
            output.prefix_key_count := norm_count.recs;

            output.lev_distance := NULLIF(evergreen.levenshtein_damerau_edistance(norm_test, norm_sugg, c_max_phrase_edit_distance * CARDINALITY(parsed_query_set)), -1);
            output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(norm_test, norm_sugg);
            output.pg_trgm_sim := similarity(norm_input, norm_sugg);
            output.soundex_sim := difference(norm_input, norm_sugg) / 4.0;

            RETURN NEXT output;
        END IF;

        IF c_variant_authority_suggestion THEN
            FOR auth_sugg IN
                SELECT  DISTINCT m.value AS prefix_key,
                        m.sort_value AS suggestion,
                        v.value as raw_input,
                        v.sort_value as norm_input
                  FROM  authority.simple_heading v
                        JOIN authority.control_set_authority_field csaf ON (csaf.id = v.atag)
                        JOIN authority.heading_field f ON (f.id = csaf.heading_field)
                        JOIN authority.simple_heading m ON (m.record = v.record AND csaf.main_entry = m.atag)
                        JOIN authority.control_set_bib_field csbf ON (csbf.authority_field = csaf.main_entry)
                        JOIN authority.control_set_bib_field_metabib_field_map csbfmfm ON (csbf.id = csbfmfm.bib_field)
                        JOIN config.metabib_field cmf ON (
                                csbfmfm.metabib_field = cmf.id
                                AND (c_authority_class_restrict IS FALSE OR cmf.field_class = search_class)
                                AND (search_fields = '{}'::TEXT[] OR cmf.name = ANY (search_fields))
                        )
                  WHERE v.sort_value = norm_sugg
            LOOP
                EXECUTE 'SELECT  COUNT(DISTINCT source) AS recs
                           FROM  metabib.' || search_class || '_field_entry
                           WHERE index_vector @@ plainto_tsquery($$simple$$,$1)' || query_part
                        INTO auth_entry USING auth_sugg.suggestion;
                IF auth_entry.recs >= c_min_suggestion_use_threshold AND (norm_count.recs = 0 OR auth_sugg.suggestion <> norm_input) THEN
                    output.input := auth_sugg.raw_input;
                    output.norm_input := auth_sugg.norm_input;
                    output.suggestion := auth_sugg.suggestion;
                    output.prefix_key := auth_sugg.prefix_key;
                    output.suggestion_count := auth_entry.recs * -1; -- negative value here 

                    output.lev_distance := 0;
                    output.qwerty_kb_match := 0;
                    output.pg_trgm_sim := 0;
                    output.soundex_sim := 0;

                    RETURN NEXT output;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    RETURN;
END;
$F$ LANGUAGE PLPGSQL;

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
