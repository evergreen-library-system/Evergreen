BEGIN;

-- 0425
ALTER TABLE permission.grp_tree
        ADD COLUMN hold_priority INT NOT NULL DEFAULT 0;

-- 0430
ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN strict_ou_match BOOL NOT NULL DEFAULT FALSE;

-- 0498
-- Rather than polluting the public schema with general Evergreen
-- functions, carve out a dedicated schema
CREATE SCHEMA evergreen;

-- Replace all uses of PostgreSQL's built-in LOWER() function with
-- a more locale-savvy PLPERLU evergreen.lowercase() function
CREATE OR REPLACE FUNCTION evergreen.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

-- 0500
CREATE OR REPLACE FUNCTION evergreen.change_db_setting(setting_name TEXT, settings TEXT[]) RETURNS VOID AS $$
BEGIN
EXECUTE 'ALTER DATABASE ' || quote_ident(current_database()) || ' SET ' || quote_ident(setting_name) || ' = ' || array_to_string(settings, ',');
END;

$$ LANGUAGE plpgsql;

-- 0501
SELECT evergreen.change_db_setting('search_path', ARRAY['evergreen','public','pg_catalog']);

-- Fix function breakage due to short search path
CREATE OR REPLACE FUNCTION evergreen.force_unicode_normal_form(string TEXT, form TEXT) RETURNS TEXT AS $func$
use Unicode::Normalize 'normalize';
return normalize($_[1],$_[0]); # reverse the params
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.facet_force_nfc() RETURNS TRIGGER AS $$
BEGIN
    NEW.value := force_unicode_normal_form(NEW.value,'NFC');
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.xml_escape(str TEXT) RETURNS text AS $$
    SELECT REPLACE(REPLACE(REPLACE($1,
       '&', '&amp;'),
       '<', '&lt;'),
       '>', '&gt;');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.maintain_901 () RETURNS TRIGGER AS $func$
DECLARE
    use_id_for_tcn BOOLEAN;
BEGIN
    -- Remove any existing 901 fields before we insert the authoritative one
    NEW.marc := REGEXP_REPLACE(NEW.marc, E'<datafield[^>]*?tag="901".+?</datafield>', '', 'g');

    IF TG_TABLE_SCHEMA = 'biblio' THEN
        -- Set TCN value to record ID?
        SELECT enabled FROM config.global_flag INTO use_id_for_tcn
            WHERE name = 'cat.bib.use_id_for_tcn';

        IF use_id_for_tcn = 't' THEN
            NEW.tcn_value := NEW.id;
        END IF;

        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="a">' || evergreen.xml_escape(NEW.tcn_value) || E'</subfield>' ||
                '<subfield code="b">' || evergreen.xml_escape(NEW.tcn_source) || E'</subfield>' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                CASE WHEN NEW.owner IS NOT NULL THEN '<subfield code="o">' || NEW.owner || E'</subfield>' ELSE '' END ||
                CASE WHEN NEW.share_depth IS NOT NULL THEN '<subfield code="d">' || NEW.share_depth || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'authority' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'serial' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                '<subfield code="o">' || NEW.owning_lib || E'</subfield>' ||
                CASE WHEN NEW.record IS NOT NULL THEN '<subfield code="r">' || NEW.record || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSE
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT) RETURNS anyarray AS $$ SELECT ARRAY_ACCUM(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2; $$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION evergreen.lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;
    my $pad = shift;
    my $len = shift;
    my $find = $len - 1;

    while ($string =~ /(?:^|\D)(\d{1,$find})(?:$|\D)/) {
        my $padded = $1;
        $padded = $pad x ($len - length($padded)) . $padded;
        $string =~ s/$1/$padded/sg;
    }

    return $string;
$$ LANGUAGE PLPERLU;

-- 0477
ALTER TABLE config.hard_due_date DROP CONSTRAINT hard_due_date_name_check;

-- 0478
CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = decode_utf8(shift);
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # http://www.loc.gov/catdir/pcc/naco/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

-- 0479
CREATE OR REPLACE FUNCTION permission.grp_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE grp_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT pgt.parent, gad.distance+1
            FROM permission.grp_tree pgt JOIN grp_ancestors_distance gad ON pgt.id = gad.id
            WHERE pgt.parent IS NOT NULL
    )
    SELECT * FROM grp_ancestors_distance;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION permission.grp_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE grp_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT pgt.id, gdd.distance+1
            FROM permission.grp_tree pgt JOIN grp_descendants_distance gdd ON pgt.parent = gdd.id
    )
    SELECT * FROM grp_descendants_distance;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON ou.id = ouad.id
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT * FROM org_unit_ancestors_distance;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.id, oudd.distance+1
            FROM actor.org_unit ou JOIN org_unit_descendants_distance oudd ON ou.parent_ou = oudd.id
    )
    SELECT * FROM org_unit_descendants_distance;
$$ LANGUAGE SQL STABLE;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN user_home_ou         INT     REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE config.circ_matrix_weights (
    id                      SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    org_unit                NUMERIC(6,2)   NOT NULL,
    grp                     NUMERIC(6,2)   NOT NULL,
    circ_modifier           NUMERIC(6,2)   NOT NULL,
    marc_type               NUMERIC(6,2)   NOT NULL,
    marc_form               NUMERIC(6,2)   NOT NULL,
    marc_vr_format          NUMERIC(6,2)   NOT NULL,
    copy_circ_lib           NUMERIC(6,2)   NOT NULL,
    copy_owning_lib         NUMERIC(6,2)   NOT NULL,
    user_home_ou            NUMERIC(6,2)   NOT NULL,
    ref_flag                NUMERIC(6,2)   NOT NULL,
    juvenile_flag           NUMERIC(6,2)   NOT NULL,
    is_renewal              NUMERIC(6,2)   NOT NULL,
    usr_age_lower_bound     NUMERIC(6,2)   NOT NULL,
    usr_age_upper_bound     NUMERIC(6,2)   NOT NULL
);

CREATE TABLE config.hold_matrix_weights (
    id                      SERIAL  PRIMARY KEY,
    name                    TEXT    NOT NULL UNIQUE,
    user_home_ou            NUMERIC(6,2)   NOT NULL,
    request_ou              NUMERIC(6,2)   NOT NULL,
    pickup_ou               NUMERIC(6,2)   NOT NULL,
    item_owning_ou          NUMERIC(6,2)   NOT NULL,
    item_circ_ou            NUMERIC(6,2)   NOT NULL,
    usr_grp                 NUMERIC(6,2)   NOT NULL,
    requestor_grp           NUMERIC(6,2)   NOT NULL,
    circ_modifier           NUMERIC(6,2)   NOT NULL,
    marc_type               NUMERIC(6,2)   NOT NULL,
    marc_form               NUMERIC(6,2)   NOT NULL,
    marc_vr_format          NUMERIC(6,2)   NOT NULL,
    juvenile_flag           NUMERIC(6,2)   NOT NULL,
    ref_flag                NUMERIC(6,2)   NOT NULL
);

CREATE TABLE config.weight_assoc (
    id                      SERIAL  PRIMARY KEY,
    active                  BOOL    NOT NULL,
    org_unit                INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    circ_weights            INT     REFERENCES config.circ_matrix_weights (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    hold_weights            INT     REFERENCES config.hold_matrix_weights (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX cwa_one_active_per_ou ON config.weight_assoc (org_unit) WHERE active;

INSERT INTO config.circ_matrix_weights(name, org_unit, grp, circ_modifier, marc_type, marc_form, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_upper_bound, usr_age_lower_bound) VALUES 
    ('Default', 10.0, 11.0, 5.0, 4.0, 3.0, 2.0, 8.0, 8.0, 8.0, 1.0, 6.0, 7.0, 0.0, 0.0),
    ('Org_Unit_First', 11.0, 10.0, 5.0, 4.0, 3.0, 2.0, 8.0, 8.0, 8.0, 1.0, 6.0, 7.0, 0.0, 0.0),
    ('Item_Owner_First', 8.0, 8.0, 5.0, 4.0, 3.0, 2.0, 10.0, 11.0, 8.0, 1.0, 6.0, 7.0, 0.0, 0.0),
    ('All_Equal', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

INSERT INTO config.hold_matrix_weights(name, user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_vr_format, juvenile_flag, ref_flag) VALUES
    ('Default', 5.0, 5.0, 5.0, 5.0, 5.0, 7.0, 8.0, 4.0, 3.0, 2.0, 1.0, 4.0, 0.0),
    ('Item_Owner_First', 5.0, 5.0, 5.0, 8.0, 7.0, 5.0, 5.0, 4.0, 3.0, 2.0, 1.0, 4.0, 0.0),
    ('User_Before_Requestor', 5.0, 5.0, 5.0, 5.0, 5.0, 8.0, 7.0, 4.0, 3.0, 2.0, 1.0, 4.0, 0.0),
    ('All_Equal', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

INSERT INTO config.weight_assoc(active, org_unit, circ_weights, hold_weights) VALUES
    (true, 1, 1, 1);

-- 0480
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

	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
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
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_note WHERE usr = src_usr;
	UPDATE actor.usr_note SET creator = dest_usr WHERE creator = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;

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

END;
$$ LANGUAGE plpgsql;

-- 0482
-- Drop old (non-functional) constraints

ALTER TABLE config.circ_matrix_matchpoint
    DROP CONSTRAINT ep_once_per_grp_loc_mod_marc;

ALTER TABLE config.hold_matrix_matchpoint
    DROP CONSTRAINT hous_once_per_grp_loc_mod_marc;

-- Clean up tables before making normalized index

CREATE OR REPLACE FUNCTION action.cleanup_matrix_matchpoints() RETURNS void AS $func$
DECLARE
    temp_row    RECORD;
BEGIN
    -- Circ Matrix
    FOR temp_row IN
        SELECT org_unit, grp, circ_modifier, marc_type, marc_form, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_lower_bound, usr_age_upper_bound, COUNT(id) as rowcount, MIN(id) as firstrow
        FROM config.circ_matrix_matchpoint
        WHERE active
        GROUP BY org_unit, grp, circ_modifier, marc_type, marc_form, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_lower_bound, usr_age_upper_bound
        HAVING COUNT(id) > 1 LOOP

        UPDATE config.circ_matrix_matchpoint SET active=false
            WHERE id > temp_row.firstrow
                AND org_unit = temp_row.org_unit
                AND grp = temp_row.grp
                AND circ_modifier       IS NOT DISTINCT FROM temp_row.circ_modifier
                AND marc_type           IS NOT DISTINCT FROM temp_row.marc_type
                AND marc_form           IS NOT DISTINCT FROM temp_row.marc_form
                AND marc_vr_format      IS NOT DISTINCT FROM temp_row.marc_vr_format
                AND copy_circ_lib       IS NOT DISTINCT FROM temp_row.copy_circ_lib
                AND copy_owning_lib     IS NOT DISTINCT FROM temp_row.copy_owning_lib
                AND user_home_ou        IS NOT DISTINCT FROM temp_row.user_home_ou
                AND ref_flag            IS NOT DISTINCT FROM temp_row.ref_flag
                AND juvenile_flag       IS NOT DISTINCT FROM temp_row.juvenile_flag
                AND is_renewal          IS NOT DISTINCT FROM temp_row.is_renewal
                AND usr_age_lower_bound IS NOT DISTINCT FROM temp_row.usr_age_lower_bound
                AND usr_age_upper_bound IS NOT DISTINCT FROM temp_row.usr_age_upper_bound;
    END LOOP;

    -- Hold Matrix
    FOR temp_row IN
        SELECT user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_vr_format, juvenile_flag, ref_flag, COUNT(id) as rowcount, MIN(id) as firstrow
        FROM config.hold_matrix_matchpoint
        WHERE active
        GROUP BY user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_vr_format, juvenile_flag, ref_flag
        HAVING COUNT(id) > 1 LOOP

        UPDATE config.hold_matrix_matchpoint SET active=false
            WHERE id > temp_row.firstrow
                AND user_home_ou        IS NOT DISTINCT FROM temp_row.user_home_ou
                AND request_ou          IS NOT DISTINCT FROM temp_row.request_ou
                AND pickup_ou           IS NOT DISTINCT FROM temp_row.pickup_ou
                AND item_owning_ou      IS NOT DISTINCT FROM temp_row.item_owning_ou
                AND item_circ_ou        IS NOT DISTINCT FROM temp_row.item_circ_ou
                AND usr_grp             IS NOT DISTINCT FROM temp_row.usr_grp
                AND requestor_grp       IS NOT DISTINCT FROM temp_row.requestor_grp
                AND circ_modifier       IS NOT DISTINCT FROM temp_row.circ_modifier
                AND marc_type           IS NOT DISTINCT FROM temp_row.marc_type
                AND marc_form           IS NOT DISTINCT FROM temp_row.marc_form
                AND marc_vr_format      IS NOT DISTINCT FROM temp_row.marc_vr_format
                AND juvenile_flag       IS NOT DISTINCT FROM temp_row.juvenile_flag
                AND ref_flag            IS NOT DISTINCT FROM temp_row.ref_flag;
    END LOOP;
END;
$func$ LANGUAGE plpgsql;

SELECT action.cleanup_matrix_matchpoints();

DROP FUNCTION IF EXISTS action.cleanup_matrix_matchpoints();

-- Create Normalized indexes

CREATE UNIQUE INDEX ccmm_once_per_paramset ON config.circ_matrix_matchpoint (org_unit, grp, COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_vr_format, ''), COALESCE(copy_circ_lib::TEXT, ''), COALESCE(copy_owning_lib::TEXT, ''), COALESCE(user_home_ou::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(is_renewal::TEXT, ''), COALESCE(usr_age_lower_bound::TEXT, ''), COALESCE(usr_age_upper_bound::TEXT, '')) WHERE active;

CREATE UNIQUE INDEX chmm_once_per_paramset ON config.hold_matrix_matchpoint (COALESCE(user_home_ou::TEXT, ''), COALESCE(request_ou::TEXT, ''), COALESCE(pickup_ou::TEXT, ''), COALESCE(item_owning_ou::TEXT, ''), COALESCE(item_circ_ou::TEXT, ''), COALESCE(usr_grp::TEXT, ''), COALESCE(requestor_grp::TEXT, ''), COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_vr_format, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(ref_flag::TEXT, '')) WHERE active;

-- 0484
DROP FUNCTION asset.metarecord_copy_count ( INT, BIGINT, BOOL );
DROP FUNCTION asset.record_copy_count ( INT, BIGINT, BOOL );

DROP FUNCTION asset.opac_ou_record_copy_count (INT, BIGINT);
CREATE OR REPLACE FUNCTION asset.opac_ou_record_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM  
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = rid AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.copy_id)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.opac_lasso_record_copy_count (INT, BIGINT);
CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM  
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = rid AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.copy_id)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.staff_ou_record_copy_count (INT, BIGINT);

DROP FUNCTION asset.staff_lasso_record_copy_count (INT, BIGINT);

CREATE OR REPLACE FUNCTION asset.record_copy_count ( place INT, rid BIGINT, staff BOOL) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
BEGIN
    IF staff IS TRUE THEN
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.staff_ou_record_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.staff_lasso_record_copy_count( -place, rid );
        END IF;
    ELSE
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.opac_ou_record_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.opac_lasso_record_copy_count( -place, rid );
        END IF;
    END IF;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.opac_ou_metarecord_copy_count (INT, BIGINT);
CREATE OR REPLACE FUNCTION asset.opac_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = rid AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.copy_id)
                JOIN metabib.metarecord_source_map m ON (m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.opac_lasso_metarecord_copy_count (INT, BIGINT);
CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = rid AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.copy_id)
                JOIN metabib.metarecord_source_map m ON (m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.staff_lasso_metarecord_copy_count (INT, BIGINT);

CREATE OR REPLACE FUNCTION asset.metarecord_copy_count ( place INT, rid BIGINT, staff BOOL) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
BEGIN
    IF staff IS TRUE THEN
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.staff_ou_metarecord_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.staff_lasso_metarecord_copy_count( -place, rid );
        END IF;
    ELSE
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.opac_ou_metarecord_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.opac_lasso_metarecord_copy_count( -place, rid );
        END IF;
    END IF;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

-- 0485
CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT	r.id,
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
	ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
	ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
	ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM	biblio.record_entry r
	JOIN metabib.metarecord_source_map s ON (s.source = r.id)
	LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
	LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
	LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
	LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

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
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

-- 0486
ALTER TABLE money.credit_card_payment ADD COLUMN cc_order_number TEXT;

-- 0487
-- Circ matchpoint table changes
ALTER TABLE config.circ_matrix_matchpoint
    ALTER COLUMN circulate DROP NOT NULL, -- Fallthrough enable
    ALTER COLUMN circulate DROP DEFAULT, -- Stop defaulting to true to enable default to fallthrough
    ALTER COLUMN duration_rule DROP NOT NULL, -- Fallthrough enable
    ALTER COLUMN recurring_fine_rule DROP NOT NULL, -- Fallthrough enable
    ALTER COLUMN max_fine_rule DROP NOT NULL, -- Fallthrough enable
    ADD COLUMN renewals INT; -- Renewals override

-- Changing return types requires explicit dropping of old versions
DROP FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL );
DROP FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL );
DROP FUNCTION action.item_user_circ_test( INT, BIGINT, INT );
DROP FUNCTION action.item_user_renew_test( INT, BIGINT, INT );

-- New return types
CREATE TYPE action.found_circ_matrix_matchpoint AS ( success BOOL, matchpoint config.circ_matrix_matchpoint, buildrows INT[] );

-- Helper function - For manual calling, it can be easier to pass in IDs instead of objects
CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.found_circ_matrix_matchpoint AS $func$
DECLARE
    item_object asset.copy%ROWTYPE;
    user_object actor.usr%ROWTYPE;
BEGIN
    SELECT INTO item_object * FROM asset.copy 	WHERE id = match_item;
    SELECT INTO user_object * FROM actor.usr	WHERE id = match_user;

    RETURN QUERY SELECT * FROM action.find_circ_matrix_matchpoint( context_ou, item_object, user_object, renewal );
END;
$func$ LANGUAGE plpgsql;

CREATE TYPE action.circ_matrix_test_result AS ( success BOOL, fail_part TEXT, buildrows INT[], matchpoint INT, circulate BOOL, duration_rule INT, recurring_fine_rule INT, max_fine_rule INT, hard_due_date INT, renewals INT, grace_period INTERVAL );

CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.circ_matrix_test_result AS $func$
DECLARE
    user_object             actor.usr%ROWTYPE;
    standing_penalty        config.standing_penalty%ROWTYPE;
    item_object             asset.copy%ROWTYPE;
    item_status_object      config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result                  action.circ_matrix_test_result;
    circ_test               action.found_circ_matrix_matchpoint;
    circ_matchpoint         config.circ_matrix_matchpoint%ROWTYPE;
    out_by_circ_mod         config.circ_matrix_circ_mod_test%ROWTYPE;
    circ_mod_map            config.circ_matrix_circ_mod_test_map%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
    result.success := TRUE;

    -- Fail if the user is BARRED
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Fail if we couldn't find the user 
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate
    IF item_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item isn't in a circulateable status on a non-renewal
    IF NOT renewal AND item_object.status NOT IN ( 0, 7, 8 ) THEN 
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    ELSIF renewal AND item_object.status <> 1 THEN
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate because of the shelving location
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;
    IF item_location_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy_location.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, item_object, user_object, renewal);

    circ_matchpoint             := circ_test.matchpoint;
    result.matchpoint           := circ_matchpoint.id;
    result.circulate            := circ_matchpoint.circulate;
    result.duration_rule        := circ_matchpoint.duration_rule;
    result.recurring_fine_rule  := circ_matchpoint.recurring_fine_rule;
    result.max_fine_rule        := circ_matchpoint.max_fine_rule;
    result.hard_due_date        := circ_matchpoint.hard_due_date;
    result.renewals             := circ_matchpoint.renewals;
    result.buildrows            := circ_test.buildrows;

    -- Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN; -- All tests after this point require a matchpoint. No sense in running on an incomplete or missing one.
    END IF;

    -- Apparently....use the circ matchpoint org unit to determine what org units are valid.
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( circ_matchpoint.org_unit );

    IF renewal THEN
        penalty_type = '%RENEW%';
    ELSE
        penalty_type = '%CIRC%';
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE penalty_type LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the test is set to hard non-circulating
    IF circ_matchpoint.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the total copy-hold ratio is too low
    IF circ_matchpoint.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_matchpoint.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_matchpoint.available_copy_hold_ratio IS NOT NULL THEN
        IF hold_ratio.hold_count IS NULL THEN
            SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        END IF;
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_matchpoint.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the user has too many items with specific circ_modifiers checked out
    FOR out_by_circ_mod IN SELECT * FROM config.circ_matrix_circ_mod_test WHERE matchpoint = circ_matchpoint.id LOOP
        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
            JOIN asset.copy cp ON (cp.id = circ.target_copy)
          WHERE circ.usr = match_user
               AND circ.circ_lib IN ( SELECT * FROM unnest(context_org_list) )
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
            AND cp.circ_modifier IN (SELECT circ_mod FROM config.circ_matrix_circ_mod_test_map WHERE circ_mod_test = out_by_circ_mod.id);
        IF items_out >= out_by_circ_mod.items_out THEN
            result.fail_part := 'config.circ_matrix_circ_mod_test';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END LOOP;

    -- If we passed everything, return the successful matchpoint id
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.item_user_circ_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, FALSE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.item_user_renew_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, TRUE );
$func$ LANGUAGE SQL;

-- 0490
CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE         
    ans RECORD; 
    trans INT;
BEGIN           
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION asset.staff_ou_metarecord_copy_count (INT, BIGINT);
CREATE OR REPLACE FUNCTION asset.staff_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE         
    ans RECORD; 
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;


-- 0493
UPDATE config.org_unit_setting_type
    SET description = 'Amount of time before a hold expires at which point the patron should be alerted. Examples: "5 days", "1 hour"'
    WHERE label = 'Holds: Expire Alert Interval';

UPDATE config.org_unit_setting_type
    SET description = 'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the default estimated length of time to assume an item will be checked out. Examples: "3 weeks", "7 days"'
    WHERE label = 'Holds: Default Estimated Wait';

UPDATE config.org_unit_setting_type
    SET description = 'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the minimum estimated length of time to assume an item will be checked out. Examples: "1 week", "5 days"'
    WHERE label = 'Holds: Minimum Estimated Wait';

UPDATE config.org_unit_setting_type
    SET description = 'The purpose is to provide an interval of time after an item goes into the on-holds-shelf status before it appears to patrons that it is actually on the holds shelf.  This gives staff time to process the item before it shows as ready-for-pickup. Examples: "5 days", "1 hour"'
    WHERE label = 'Hold Shelf Status Delay';

-- 0494
UPDATE config.metabib_field
    SET xpath = $$//mods32:mods/mods32:subject$$
    WHERE field_class = 'subject' AND name = 'complete';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='099']$$
    WHERE field_class = 'identifier' AND name = 'bibcn';

-- 0495
CREATE TABLE config.record_attr_definition (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL, -- I18N
    description TEXT,
    filter      BOOL    NOT NULL DEFAULT TRUE,  -- becomes QP filter if true
    sorter      BOOL    NOT NULL DEFAULT FALSE, -- becomes QP sort() axis if true

-- For pre-extracted fields. Takes the first occurance, uses naive subfield ordering
    tag         TEXT, -- LIKE format
    sf_list     TEXT, -- pile-o-values, like 'abcd' for a and b and c and d

-- This is used for both tag/sf and xpath entries
    joiner      TEXT,

-- For xpath-extracted attrs
    xpath       TEXT,
    format      TEXT    REFERENCES config.xml_transform (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    start_pos   INT,
    string_len  INT,

-- For fixed fields
    fixed_field TEXT, -- should exist in config.marc21_ff_pos_map.fixed_field

-- For phys-char fields
    phys_char_sf    INT REFERENCES config.marc21_physical_characteristic_subfield_map (id)
);

CREATE TABLE config.record_attr_index_norm_map (
    id      SERIAL  PRIMARY KEY,
    attr    TEXT    NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    params  TEXT,
    pos     INT     NOT NULL DEFAULT 0
);

CREATE TABLE config.coded_value_map (
    id          SERIAL  PRIMARY KEY,
    ctype       TEXT    NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    code        TEXT    NOT NULL,
    value       TEXT    NOT NULL,
    description TEXT
);

-- record attributes
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('alph','Alph','Alph');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('audience','Audn','Audn');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('bib_level','BLvl','BLvl');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('biog','Biog','Biog');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('conf','Conf','Conf');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('control_type','Ctrl','Ctrl');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('ctry','Ctry','Ctry');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('date1','Date1','Date1');
INSERT INTO config.record_attr_definition (name,label,fixed_field,sorter,filter) values ('pubdate','Pub Date','Date1',TRUE,FALSE);
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('date2','Date2','Date2');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('cat_form','Desc','Desc');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('pub_status','DtSt','DtSt');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('enc_level','ELvl','ELvl');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('fest','Fest','Fest');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('item_form','Form','Form');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('gpub','GPub','GPub');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('ills','Ills','Ills');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('indx','Indx','Indx');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('item_lang','Lang','Lang');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('lit_form','LitF','LitF');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('mrec','MRec','MRec');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('ff_sl','S/L','S/L');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('type_mat','TMat','TMat');
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('item_type','Type','Type');
INSERT INTO config.record_attr_definition (name,label,phys_char_sf) values ('vr_format','Videorecording format',72);
INSERT INTO config.record_attr_definition (name,label,sorter,filter,tag) values ('titlesort','Title',TRUE,FALSE,'tnf');
INSERT INTO config.record_attr_definition (name,label,sorter,filter,tag) values ('authorsort','Author',TRUE,FALSE,'1%');

INSERT INTO config.coded_value_map (ctype,code,value,description)
    SELECT 'item_lang' AS ctype, code, value, NULL FROM config.language_map
        UNION
    SELECT 'bib_level' AS ctype, code, value, NULL FROM config.bib_level_map
        UNION
    SELECT 'item_form' AS ctype, code, value, NULL FROM config.item_form_map
        UNION
    SELECT 'item_type' AS ctype, code, value, NULL FROM config.item_type_map
        UNION
    SELECT 'lit_form' AS ctype, code, value, description FROM config.lit_form_map
        UNION
    SELECT 'audience' AS ctype, code, value, description FROM config.audience_map
        UNION
    SELECT 'vr_format' AS ctype, code, value, NULL FROM config.videorecording_format_map;

ALTER TABLE config.i18n_locale DROP CONSTRAINT i18n_locale_marc_code_fkey;

ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT circ_matrix_matchpoint_marc_form_fkey;
ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT circ_matrix_matchpoint_marc_type_fkey;
ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT circ_matrix_matchpoint_marc_vr_format_fkey;

ALTER TABLE config.hold_matrix_matchpoint DROP CONSTRAINT hold_matrix_matchpoint_marc_form_fkey;
ALTER TABLE config.hold_matrix_matchpoint DROP CONSTRAINT hold_matrix_matchpoint_marc_type_fkey;
ALTER TABLE config.hold_matrix_matchpoint DROP CONSTRAINT hold_matrix_matchpoint_marc_vr_format_fkey;

DROP TABLE config.language_map;
DROP TABLE config.bib_level_map;
DROP TABLE config.item_form_map;
DROP TABLE config.item_type_map;
DROP TABLE config.lit_form_map;
DROP TABLE config.audience_map;
DROP TABLE config.videorecording_format_map;

UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'clm.value' AND ccvm.ctype = 'item_lang' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cblvl.value' AND ccvm.ctype = 'bib_level' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cifm.value' AND ccvm.ctype = 'item_form' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'citm.value' AND ccvm.ctype = 'item_type' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'clfm.value' AND ccvm.ctype = 'lit_form' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cam.value' AND ccvm.ctype = 'audience' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.value', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cvrfm.value' AND ccvm.ctype = 'vr_format' AND identity_value = ccvm.code;

UPDATE config.i18n_core SET fq_field = 'ccvm.description', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'clfm.description' AND ccvm.ctype = 'lit_form' AND identity_value = ccvm.code;
UPDATE config.i18n_core SET fq_field = 'ccvm.description', identity_value = ccvm.id FROM config.coded_value_map AS ccvm WHERE fq_field = 'cam.description' AND ccvm.ctype = 'audience' AND identity_value = ccvm.code;

CREATE VIEW config.language_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_lang';
CREATE VIEW config.bib_level_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'bib_level';
CREATE VIEW config.item_form_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_form';
CREATE VIEW config.item_type_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_type';
CREATE VIEW config.lit_form_map AS SELECT code, value, description FROM config.coded_value_map WHERE ctype = 'lit_form';
CREATE VIEW config.audience_map AS SELECT code, value, description FROM config.coded_value_map WHERE ctype = 'audience';
CREATE VIEW config.videorecording_format_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'vr_format';

CREATE TABLE metabib.record_attr (
       id              BIGINT  PRIMARY KEY REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
       attrs   HSTORE  NOT NULL DEFAULT ''::HSTORE
);
CREATE INDEX metabib_svf_attrs_idx ON metabib.record_attr USING GIST (attrs);
CREATE INDEX metabib_svf_date1_idx ON metabib.record_attr ( (attrs->'date1') );
CREATE INDEX metabib_svf_dates_idx ON metabib.record_attr ( (attrs->'date1'), (attrs->'date2') );

INSERT INTO metabib.record_attr (id,attrs)
    SELECT mrd.record, hstore(mrd) - '{id,record}'::TEXT[] FROM metabib.rec_descriptor mrd;

-- Back-compat view ... we're moving to an HSTORE world
CREATE TYPE metabib.rec_desc_type AS (
    item_type       TEXT,
    item_form       TEXT,
    bib_level       TEXT,
    control_type    TEXT,
    char_encoding   TEXT,
    enc_level       TEXT,
    audience        TEXT,
    lit_form        TEXT,
    type_mat        TEXT,
    cat_form        TEXT,
    pub_status      TEXT,
    item_lang       TEXT,
    vr_format       TEXT,
    date1           TEXT,
    date2           TEXT
);

DROP TABLE metabib.rec_descriptor CASCADE;

CREATE VIEW metabib.rec_descriptor AS
    SELECT  id,
            id AS record,
            (populate_record(NULL::metabib.rec_desc_type, attrs)).*
      FROM  metabib.record_attr;

CREATE OR REPLACE FUNCTION vandelay.marc21_record_type( marc TEXT ) RETURNS config.marc21_rec_type_map AS $func$
DECLARE
    ldr         TEXT;
    tval        TEXT;
    tval_rec    RECORD;
    bval        TEXT;
    bval_rec    RECORD;
    retval      config.marc21_rec_type_map%ROWTYPE;
BEGIN
    ldr := oils_xpath_string( '//*[local-name()="leader"]', marc );

    IF ldr IS NULL OR ldr = '' THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
        RETURN retval;
    END IF;

    SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
    SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


    tval := SUBSTRING( ldr, tval_rec.start_pos + 1, tval_rec.length );
    bval := SUBSTRING( ldr, bval_rec.start_pos + 1, bval_rec.length );

    -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr;

    SELECT * INTO retval FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';


    IF retval.code IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
    END IF;

    RETURN retval;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_record_type( rid BIGINT ) RETURNS config.marc21_rec_type_map AS $func$
    SELECT * FROM vandelay.marc21_record_type( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field( marc TEXT, ff TEXT ) RETURNS TEXT AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
            val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
            RETURN val;
        END LOOP;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        RETURN val;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field( rid BIGINT, ff TEXT ) RETURNS TEXT AS $func$
    SELECT * FROM vandelay.marc21_extract_fixed_field( (SELECT marc FROM biblio.record_entry WHERE id = $1), $2 );
$func$ LANGUAGE SQL;

CREATE TYPE biblio.record_ff_map AS (record BIGINT, ff_name TEXT, ff_value TEXT);
CREATE OR REPLACE FUNCTION vandelay.marc21_extract_all_fixed_fields( marc TEXT ) RETURNS SETOF biblio.record_ff_map AS $func$
DECLARE
    tag_data    TEXT;
    rtype       TEXT;
    ff_pos      RECORD;
    output      biblio.record_ff_map%ROWTYPE;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;

    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE rec_type = rtype ORDER BY tag DESC LOOP
        output.ff_name  := ff_pos.fixed_field;
        output.ff_value := NULL;

        FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(tag) || '"]/text()', marc ) ) x(value) LOOP
            output.ff_value := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
            IF output.ff_value IS NULL THEN output.ff_value := REPEAT( ff_pos.default_val, ff_pos.length ); END IF;
            RETURN NEXT output;
            output.ff_value := NULL;
        END LOOP;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_all_fixed_fields( rid BIGINT ) RETURNS SETOF biblio.record_ff_map AS $func$
    SELECT $1 AS record, ff_name, ff_value FROM vandelay.marc21_extract_all_fixed_fields( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_physical_characteristics( marc TEXT) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
DECLARE
    rowid   INT := 0;
    _007    TEXT;
    ptype   config.marc21_physical_characteristic_type_map%ROWTYPE;
    psf     config.marc21_physical_characteristic_subfield_map%ROWTYPE;
    pval    config.marc21_physical_characteristic_value_map%ROWTYPE;
    retval  biblio.marc21_physical_characteristics%ROWTYPE;
BEGIN

    _007 := oils_xpath_string( '//*[@tag="007"]', marc );

    IF _007 IS NOT NULL AND _007 <> '' THEN
        SELECT * INTO ptype FROM config.marc21_physical_characteristic_type_map WHERE ptype_key = SUBSTRING( _007, 1, 1 );

        IF ptype.ptype_key IS NOT NULL THEN
            FOR psf IN SELECT * FROM config.marc21_physical_characteristic_subfield_map WHERE ptype_key = ptype.ptype_key LOOP
                SELECT * INTO pval FROM config.marc21_physical_characteristic_value_map WHERE ptype_subfield = psf.id AND value = SUBSTRING( _007, psf.start_pos + 1, psf.length );

                IF pval.id IS NOT NULL THEN
                    rowid := rowid + 1;
                    retval.id := rowid;
                    retval.ptype := ptype.ptype_key;
                    retval.subfield := psf.id;
                    retval.value := pval.id;
                    RETURN NEXT retval;
                END IF;

            END LOOP;
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_physical_characteristics( rid BIGINT ) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
    SELECT id, $1 AS record, ptype, subfield, value FROM vandelay.marc21_physical_characteristics( (SELECT marc FROM biblio.record_entry WHERE id = $1) );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM metabib.record_attr WHERE id = NEW.id; -- Kill the attrs hash, useless on deleted records
        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;

                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  value::TEXT INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id)
                      WHERE subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( attr_value ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;

                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = attrs || new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION metabib.reingest_metabib_rec_descriptor( bib_id BIGINT );

CREATE OR REPLACE FUNCTION public.approximate_date( TEXT, TEXT ) RETURNS TEXT AS $func$
        SELECT REGEXP_REPLACE( $1, E'\\D', $2, 'g' );
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_low_date( TEXT ) RETURNS TEXT AS $func$
        SELECT approximate_date( $1, '0');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_high_date( TEXT ) RETURNS TEXT AS $func$
        SELECT approximate_date( $1, '9');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.integer_or_null( TEXT ) RETURNS TEXT AS $func$
        SELECT CASE WHEN $1 ~ E'^\\d+$' THEN $1 ELSE NULL END
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.content_or_null( TEXT ) RETURNS TEXT AS $func$
        SELECT CASE WHEN $1 ~ E'^\\s*$' THEN NULL ELSE $1 END
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.force_to_isbn13( TEXT ) RETURNS TEXT AS $func$
    use Business::ISBN;
    use strict;
    use warnings;

    # Find the first ISBN, force it to ISBN13 and return it

    my $input = shift;

    foreach my $word (split(/\s/, $input)) {
        my $isbn = Business::ISBN->new($word);

        # First check the checksum; if it is not valid, fix it and add the original
        # bad-checksum ISBN to the output
        if ($isbn && $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM) {
            $isbn->fix_checksum();
        }

        # If we now have a valid ISBN, force it to ISBN13 and return it
        return $isbn->as_isbn13->isbn if ($isbn && $isbn->is_valid());
    }
    return undef;
$func$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION public.force_to_isbn13(TEXT) IS $$
/*
 * Copyright (C) 2011 Equinox Software
 * Mike Rylander <mrylander@gmail.com>
 *
 * Inspired by translate_isbn1013
 *
 * The force_to_isbn13 function takes an input ISBN and returns the ISBN13
 * version without hypens and with a repaired checksum if the checksum was bad
 */
$$;

-- 0496
UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='1']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'upc';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='2']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'ismn';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='3']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'ean';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='0']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'isrc';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='024' and @ind1='4']/marc:subfield[@code='a' or @code='z']$$
    WHERE field_class = 'identifier' AND name = 'sici';

-- 0497
INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES

( 'ui.patron.edit.au.active.show',
    oils_i18n_gettext('ui.patron.edit.au.active.show', 'GUI: Show active field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.active.show', 'The active field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.active.suggest',
    oils_i18n_gettext('ui.patron.edit.au.active.suggest', 'GUI: Suggest active field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.active.suggest', 'The active field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.alert_message.show',
    oils_i18n_gettext('ui.patron.edit.au.alert_message.show', 'GUI: Show alert_message field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.alert_message.show', 'The alert_message field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.alert_message.suggest',
    oils_i18n_gettext('ui.patron.edit.au.alert_message.suggest', 'GUI: Suggest alert_message field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.alert_message.suggest', 'The alert_message field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.alias.show',
    oils_i18n_gettext('ui.patron.edit.au.alias.show', 'GUI: Show alias field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.alias.show', 'The alias field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.alias.suggest',
    oils_i18n_gettext('ui.patron.edit.au.alias.suggest', 'GUI: Suggest alias field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.alias.suggest', 'The alias field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.barred.show',
    oils_i18n_gettext('ui.patron.edit.au.barred.show', 'GUI: Show barred field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.barred.show', 'The barred field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.barred.suggest',
    oils_i18n_gettext('ui.patron.edit.au.barred.suggest', 'GUI: Suggest barred field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.barred.suggest', 'The barred field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.claims_never_checked_out_count.show',
    oils_i18n_gettext('ui.patron.edit.au.claims_never_checked_out_count.show', 'GUI: Show claims_never_checked_out_count field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.claims_never_checked_out_count.show', 'The claims_never_checked_out_count field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.claims_never_checked_out_count.suggest',
    oils_i18n_gettext('ui.patron.edit.au.claims_never_checked_out_count.suggest', 'GUI: Suggest claims_never_checked_out_count field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.claims_never_checked_out_count.suggest', 'The claims_never_checked_out_count field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.claims_returned_count.show',
    oils_i18n_gettext('ui.patron.edit.au.claims_returned_count.show', 'GUI: Show claims_returned_count field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.claims_returned_count.show', 'The claims_returned_count field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.claims_returned_count.suggest',
    oils_i18n_gettext('ui.patron.edit.au.claims_returned_count.suggest', 'GUI: Suggest claims_returned_count field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.claims_returned_count.suggest', 'The claims_returned_count field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.day_phone.example',
    oils_i18n_gettext('ui.patron.edit.au.day_phone.example', 'GUI: Example for day_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.day_phone.example', 'The Example for validation on the day_phone field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.day_phone.regex',
    oils_i18n_gettext('ui.patron.edit.au.day_phone.regex', 'GUI: Regex for day_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.day_phone.regex', 'The Regular Expression for validation on the day_phone field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.day_phone.require',
    oils_i18n_gettext('ui.patron.edit.au.day_phone.require', 'GUI: Require day_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.day_phone.require', 'The day_phone field will be required on the patron registration screen.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.day_phone.show',
    oils_i18n_gettext('ui.patron.edit.au.day_phone.show', 'GUI: Show day_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.day_phone.show', 'The day_phone field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.day_phone.suggest',
    oils_i18n_gettext('ui.patron.edit.au.day_phone.suggest', 'GUI: Suggest day_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.day_phone.suggest', 'The day_phone field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.dob.calendar',
    oils_i18n_gettext('ui.patron.edit.au.dob.calendar', 'GUI: Show calendar widget for dob field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.dob.calendar', 'If set the calendar widget will appear when editing the dob field on the patron registration form.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.dob.require',
    oils_i18n_gettext('ui.patron.edit.au.dob.require', 'GUI: Require dob field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.dob.require', 'The dob field will be required on the patron registration screen.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.dob.show',
    oils_i18n_gettext('ui.patron.edit.au.dob.show', 'GUI: Show dob field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.dob.show', 'The dob field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.dob.suggest',
    oils_i18n_gettext('ui.patron.edit.au.dob.suggest', 'GUI: Suggest dob field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.dob.suggest', 'The dob field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.email.example',
    oils_i18n_gettext('ui.patron.edit.au.email.example', 'GUI: Example for email field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.email.example', 'The Example for validation on the email field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.email.regex',
    oils_i18n_gettext('ui.patron.edit.au.email.regex', 'GUI: Regex for email field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.email.regex', 'The Regular Expression for validation on the email field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.email.require',
    oils_i18n_gettext('ui.patron.edit.au.email.require', 'GUI: Require email field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.email.require', 'The email field will be required on the patron registration screen.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.email.show',
    oils_i18n_gettext('ui.patron.edit.au.email.show', 'GUI: Show email field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.email.show', 'The email field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.email.suggest',
    oils_i18n_gettext('ui.patron.edit.au.email.suggest', 'GUI: Suggest email field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.email.suggest', 'The email field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.evening_phone.example',
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.example', 'GUI: Example for evening_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.example', 'The Example for validation on the evening_phone field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.evening_phone.regex',
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.regex', 'GUI: Regex for evening_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.regex', 'The Regular Expression for validation on the evening_phone field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.evening_phone.require',
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.require', 'GUI: Require evening_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.require', 'The evening_phone field will be required on the patron registration screen.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.evening_phone.show',
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.show', 'GUI: Show evening_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.show', 'The evening_phone field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.evening_phone.suggest',
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.suggest', 'GUI: Suggest evening_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.evening_phone.suggest', 'The evening_phone field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.ident_value.show',
    oils_i18n_gettext('ui.patron.edit.au.ident_value.show', 'GUI: Show ident_value field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.ident_value.show', 'The ident_value field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.ident_value.suggest',
    oils_i18n_gettext('ui.patron.edit.au.ident_value.suggest', 'GUI: Suggest ident_value field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.ident_value.suggest', 'The ident_value field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.ident_value2.show',
    oils_i18n_gettext('ui.patron.edit.au.ident_value2.show', 'GUI: Show ident_value2 field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.ident_value2.show', 'The ident_value2 field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.ident_value2.suggest',
    oils_i18n_gettext('ui.patron.edit.au.ident_value2.suggest', 'GUI: Suggest ident_value2 field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.ident_value2.suggest', 'The ident_value2 field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.juvenile.show',
    oils_i18n_gettext('ui.patron.edit.au.juvenile.show', 'GUI: Show juvenile field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.juvenile.show', 'The juvenile field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.juvenile.suggest',
    oils_i18n_gettext('ui.patron.edit.au.juvenile.suggest', 'GUI: Suggest juvenile field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.juvenile.suggest', 'The juvenile field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.master_account.show',
    oils_i18n_gettext('ui.patron.edit.au.master_account.show', 'GUI: Show master_account field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.master_account.show', 'The master_account field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.master_account.suggest',
    oils_i18n_gettext('ui.patron.edit.au.master_account.suggest', 'GUI: Suggest master_account field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.master_account.suggest', 'The master_account field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.other_phone.example',
    oils_i18n_gettext('ui.patron.edit.au.other_phone.example', 'GUI: Example for other_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.other_phone.example', 'The Example for validation on the other_phone field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.other_phone.regex',
    oils_i18n_gettext('ui.patron.edit.au.other_phone.regex', 'GUI: Regex for other_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.other_phone.regex', 'The Regular Expression for validation on the other_phone field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.au.other_phone.require',
    oils_i18n_gettext('ui.patron.edit.au.other_phone.require', 'GUI: Require other_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.other_phone.require', 'The other_phone field will be required on the patron registration screen.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.other_phone.show',
    oils_i18n_gettext('ui.patron.edit.au.other_phone.show', 'GUI: Show other_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.other_phone.show', 'The other_phone field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.other_phone.suggest',
    oils_i18n_gettext('ui.patron.edit.au.other_phone.suggest', 'GUI: Suggest other_phone field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.other_phone.suggest', 'The other_phone field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.second_given_name.show',
    oils_i18n_gettext('ui.patron.edit.au.second_given_name.show', 'GUI: Show second_given_name field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.second_given_name.show', 'The second_given_name field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.second_given_name.suggest',
    oils_i18n_gettext('ui.patron.edit.au.second_given_name.suggest', 'GUI: Suggest second_given_name field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.second_given_name.suggest', 'The second_given_name field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.suffix.show',
    oils_i18n_gettext('ui.patron.edit.au.suffix.show', 'GUI: Show suffix field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.suffix.show', 'The suffix field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.au.suffix.suggest',
    oils_i18n_gettext('ui.patron.edit.au.suffix.suggest', 'GUI: Suggest suffix field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.suffix.suggest', 'The suffix field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.aua.county.require',
    oils_i18n_gettext('ui.patron.edit.aua.county.require', 'GUI: Require county field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.aua.county.require', 'The county field will be required on the patron registration screen.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.aua.post_code.example',
    oils_i18n_gettext('ui.patron.edit.aua.post_code.example', 'GUI: Example for post_code field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.aua.post_code.example', 'The Example for validation on the post_code field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.aua.post_code.regex',
    oils_i18n_gettext('ui.patron.edit.aua.post_code.regex', 'GUI: Regex for post_code field on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.aua.post_code.regex', 'The Regular Expression for validation on the post_code field in patron registration.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.default_suggested',
    oils_i18n_gettext('ui.patron.edit.default_suggested', 'GUI: Default showing suggested patron registration fields', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.default_suggested', 'Instead of All fields, show just suggested fields in patron registration by default.', 'coust', 'description'),
    'bool'),
( 'ui.patron.edit.phone.example',
    oils_i18n_gettext('ui.patron.edit.phone.example', 'GUI: Example for phone fields on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.phone.example', 'The Example for validation on phone fields in patron registration. Applies to all phone fields without their own setting.', 'coust', 'description'),
    'string'),
( 'ui.patron.edit.phone.regex',
    oils_i18n_gettext('ui.patron.edit.phone.regex', 'GUI: Regex for phone fields on patron registration', 'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.phone.regex', 'The Regular Expression for validation on phone fields in patron registration. Applies to all phone fields without their own setting.', 'coust', 'description'),
    'string');

-- update actor.usr_address indexes
DROP INDEX IF EXISTS actor.actor_usr_addr_street1_idx;
DROP INDEX IF EXISTS actor.actor_usr_addr_street2_idx;
DROP INDEX IF EXISTS actor.actor_usr_addr_city_idx;
DROP INDEX IF EXISTS actor.actor_usr_addr_state_idx; 
DROP INDEX IF EXISTS actor.actor_usr_addr_post_code_idx;

CREATE INDEX actor_usr_addr_street1_idx ON actor.usr_address (evergreen.lowercase(street1));
CREATE INDEX actor_usr_addr_street2_idx ON actor.usr_address (evergreen.lowercase(street2));
CREATE INDEX actor_usr_addr_city_idx ON actor.usr_address (evergreen.lowercase(city));
CREATE INDEX actor_usr_addr_state_idx ON actor.usr_address (evergreen.lowercase(state));
CREATE INDEX actor_usr_addr_post_code_idx ON actor.usr_address (evergreen.lowercase(post_code));

-- update actor.usr indexes
DROP INDEX IF EXISTS actor.actor_usr_first_given_name_idx;
DROP INDEX IF EXISTS actor.actor_usr_second_given_name_idx;
DROP INDEX IF EXISTS actor.actor_usr_family_name_idx;
DROP INDEX IF EXISTS actor.actor_usr_email_idx;
DROP INDEX IF EXISTS actor.actor_usr_day_phone_idx;
DROP INDEX IF EXISTS actor.actor_usr_evening_phone_idx;
DROP INDEX IF EXISTS actor.actor_usr_other_phone_idx;
DROP INDEX IF EXISTS actor.actor_usr_ident_value_idx;
DROP INDEX IF EXISTS actor.actor_usr_ident_value2_idx;

CREATE INDEX actor_usr_first_given_name_idx ON actor.usr (evergreen.lowercase(first_given_name));
CREATE INDEX actor_usr_second_given_name_idx ON actor.usr (evergreen.lowercase(second_given_name));
CREATE INDEX actor_usr_family_name_idx ON actor.usr (evergreen.lowercase(family_name));
CREATE INDEX actor_usr_email_idx ON actor.usr (evergreen.lowercase(email));
CREATE INDEX actor_usr_day_phone_idx ON actor.usr (evergreen.lowercase(day_phone));
CREATE INDEX actor_usr_evening_phone_idx ON actor.usr (evergreen.lowercase(evening_phone));
CREATE INDEX actor_usr_other_phone_idx ON actor.usr (evergreen.lowercase(other_phone));
CREATE INDEX actor_usr_ident_value_idx ON actor.usr (evergreen.lowercase(ident_value));
CREATE INDEX actor_usr_ident_value2_idx ON actor.usr (evergreen.lowercase(ident_value2));

-- update actor.card indexes
DROP INDEX IF EXISTS actor.actor_card_barcode_evergreen_lowercase_idx;
CREATE INDEX actor_card_barcode_evergreen_lowercase_idx ON actor.card (evergreen.lowercase(barcode));

CREATE OR REPLACE FUNCTION vandelay.match_bib_record ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr        RECORD;
    attr_def    RECORD;
    eg_rec      RECORD;
    id_value    TEXT;
    exact_id    BIGINT;
BEGIN

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT * INTO attr_def FROM vandelay.bib_attr_definition WHERE xpath = '//*[@tag="901"]/*[@code="c"]' ORDER BY id LIMIT 1;

    IF attr_def IS NOT NULL AND attr_def.id IS NOT NULL THEN
        id_value := extract_marc_field('vandelay.queued_bib_record', NEW.id, attr_def.xpath, attr_def.remove);
    
        IF id_value IS NOT NULL AND id_value <> '' AND id_value ~ $r$^\d+$$r$ THEN
            SELECT id INTO exact_id FROM biblio.record_entry WHERE id = id_value::BIGINT AND NOT deleted;
            SELECT * INTO attr FROM vandelay.queued_bib_record_attr WHERE record = NEW.id and field = attr_def.id LIMIT 1;
            IF exact_id IS NOT NULL THEN
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, exact_id);
            END IF;
        END IF;
    END IF;

    IF exact_id IS NULL THEN
        FOR attr IN SELECT a.* FROM vandelay.queued_bib_record_attr a JOIN vandelay.bib_attr_definition d ON (d.id = a.field) WHERE record = NEW.id AND d.ident IS TRUE LOOP
    
    		-- All numbers? check for an id match
    		IF (attr.attr_value ~ $r$^\d+$$r$) THEN
    	        FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE id = attr.attr_value::BIGINT AND deleted IS FALSE LOOP
    		        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
    			END LOOP;
    		END IF;
    
    		-- Looks like an ISBN? check for an isbn match
    		IF (attr.attr_value ~* $r$^[0-9x]+$$r$ AND character_length(attr.attr_value) IN (10,13)) THEN
    	        FOR eg_rec IN EXECUTE $$SELECT * FROM metabib.full_rec fr WHERE fr.value LIKE evergreen.lowercase('$$ || attr.attr_value || $$%') AND fr.tag = '020' AND fr.subfield = 'a'$$ LOOP
    				PERFORM id FROM biblio.record_entry WHERE id = eg_rec.record AND deleted IS FALSE;
    				IF FOUND THEN
    			        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('isbn', attr.id, NEW.id, eg_rec.record);
    				END IF;
    			END LOOP;
    
    			-- subcheck for isbn-as-tcn
    		    FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = 'i' || attr.attr_value AND deleted IS FALSE LOOP
    			    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
    	        END LOOP;
    		END IF;
    
    		-- check for an OCLC tcn_value match
    		IF (attr.attr_value ~ $r$^o\d+$$r$) THEN
    		    FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = regexp_replace(attr.attr_value,'^o','ocm') AND deleted IS FALSE LOOP
    			    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
    	        END LOOP;
    		END IF;
    
    		-- check for a direct tcn_value match
            FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = attr.attr_value AND deleted IS FALSE LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
            END LOOP;
    
    		-- check for a direct item barcode match
            FOR eg_rec IN
                    SELECT  DISTINCT b.*
                      FROM  biblio.record_entry b
                            JOIN asset.call_number cn ON (cn.record = b.id)
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cp.barcode = attr.attr_value AND cp.deleted IS FALSE
            LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
            END LOOP;
    
        END LOOP;
    END IF;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;


-- 0499
CREATE OR REPLACE FUNCTION asset.label_normalizer_generic(TEXT) RETURNS TEXT AS $func$
    # Created after looking at the Koha C4::ClassSortRoutine::Generic module,
    # thus could probably be considered a derived work, although nothing was
    # directly copied - but to err on the safe side of providing attribution:
    # Copyright (C) 2007 LibLime
    # Copyright (C) 2011 Equinox Software, Inc (Steve Callendar)
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    # Converts the callnumber to uppercase
    # Strips spaces from start and end of the call number
    # Converts anything other than letters, digits, and periods into spaces
    # Collapses multiple spaces into a single underscore
    my $callnum = uc(shift);
    $callnum =~ s/^\s//g;
    $callnum =~ s/\s$//g;
    # NOTE: this previously used underscores, but this caused sorting issues
    # for the "before" half of page 0 on CN browse, sorting CNs containing a
    # decimal before "whole number" CNs
    $callnum =~ s/[^A-Z0-9_.]/ /g;
    $callnum =~ s/ {2,}/ /g;

    return $callnum;
$func$ LANGUAGE PLPERLU;



-- 0501
INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('language','Language (2.0 compat version)','Lang');
UPDATE metabib.record_attr SET attrs = attrs || hstore('language',(attrs->'item_lang'));

-- 0502
-- Dewey fields
UPDATE asset.call_number_class
    SET field = '080ab,082ab,092abef'
    WHERE id = 2
;

-- LC fields
UPDATE asset.call_number_class
    SET field = '050ab,055ab,090abef'
    WHERE id = 3
;

-- FAIR WARNING:
-- Using a tool such as pgadmin to run this script may fail
-- If it does, try psql command line.

-- Change this to FALSE to disable updating existing circs
-- Otherwise will use the fine interval for the grace period
\set CircGrace TRUE

-- 0503
-- New Columns

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN grace_period INTERVAL;

ALTER TABLE config.rule_recurring_fine
    ADD COLUMN grace_period INTERVAL NOT NULL DEFAULT '1 day';

ALTER TABLE action.circulation
    ADD COLUMN grace_period INTERVAL NOT NULL DEFAULT '0 seconds';

ALTER TABLE action.aged_circulation
    ADD COLUMN grace_period INTERVAL NOT NULL DEFAULT '0 seconds';

-- Remove defaults needed to stop null complaints

ALTER TABLE action.circulation
    ALTER COLUMN grace_period DROP DEFAULT;

ALTER TABLE action.aged_circulation
    ALTER COLUMN grace_period DROP DEFAULT;

-- Drop Views

DROP VIEW action.all_circulation;
DROP VIEW action.open_circulation;
DROP VIEW action.billable_circulations;

-- Replace Views

CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, cp.location AS copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = a.id);

CREATE OR REPLACE VIEW action.open_circulation AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	checkin_time IS NULL
	  ORDER BY due_date;
		

CREATE OR REPLACE VIEW action.billable_circulations AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	xact_finish IS NULL;

-- Drop Functions that rely on types

DROP FUNCTION action.item_user_circ_test(INT, BIGINT, INT, BOOL);
DROP FUNCTION action.item_user_circ_test(INT, BIGINT, INT);
DROP FUNCTION action.item_user_renew_test(INT, BIGINT, INT);

CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.circ_matrix_test_result AS $func$
DECLARE
    user_object             actor.usr%ROWTYPE;
    standing_penalty        config.standing_penalty%ROWTYPE;
    item_object             asset.copy%ROWTYPE;
    item_status_object      config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result                  action.circ_matrix_test_result;
    circ_test               action.found_circ_matrix_matchpoint;
    circ_matchpoint         config.circ_matrix_matchpoint%ROWTYPE;
    out_by_circ_mod         config.circ_matrix_circ_mod_test%ROWTYPE;
    circ_mod_map            config.circ_matrix_circ_mod_test_map%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
    result.success := TRUE;

    -- Fail if the user is BARRED
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Fail if we couldn't find the user 
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate
    IF item_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item isn't in a circulateable status on a non-renewal
    IF NOT renewal AND item_object.status NOT IN ( 0, 7, 8 ) THEN 
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    ELSIF renewal AND item_object.status <> 1 THEN
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate because of the shelving location
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;
    IF item_location_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy_location.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, item_object, user_object, renewal);

    circ_matchpoint             := circ_test.matchpoint;
    result.matchpoint           := circ_matchpoint.id;
    result.circulate            := circ_matchpoint.circulate;
    result.duration_rule        := circ_matchpoint.duration_rule;
    result.recurring_fine_rule  := circ_matchpoint.recurring_fine_rule;
    result.max_fine_rule        := circ_matchpoint.max_fine_rule;
    result.hard_due_date        := circ_matchpoint.hard_due_date;
    result.renewals             := circ_matchpoint.renewals;
    result.grace_period         := circ_matchpoint.grace_period;
    result.buildrows            := circ_test.buildrows;

    -- Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN; -- All tests after this point require a matchpoint. No sense in running on an incomplete or missing one.
    END IF;

    -- Apparently....use the circ matchpoint org unit to determine what org units are valid.
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( circ_matchpoint.org_unit );

    IF renewal THEN
        penalty_type = '%RENEW%';
    ELSE
        penalty_type = '%CIRC%';
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE penalty_type LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the test is set to hard non-circulating
    IF circ_matchpoint.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the total copy-hold ratio is too low
    IF circ_matchpoint.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_matchpoint.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_matchpoint.available_copy_hold_ratio IS NOT NULL THEN
        IF hold_ratio.hold_count IS NULL THEN
            SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        END IF;
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_matchpoint.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the user has too many items with specific circ_modifiers checked out
    FOR out_by_circ_mod IN SELECT * FROM config.circ_matrix_circ_mod_test WHERE matchpoint = circ_matchpoint.id LOOP
        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
            JOIN asset.copy cp ON (cp.id = circ.target_copy)
          WHERE circ.usr = match_user
               AND circ.circ_lib IN ( SELECT * FROM unnest(context_org_list) )
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
            AND cp.circ_modifier IN (SELECT circ_mod FROM config.circ_matrix_circ_mod_test_map WHERE circ_mod_test = out_by_circ_mod.id);
        IF items_out >= out_by_circ_mod.items_out THEN
            result.fail_part := 'config.circ_matrix_circ_mod_test';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END LOOP;

    -- If we passed everything, return the successful matchpoint id
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.item_user_circ_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, FALSE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.item_user_renew_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, TRUE );
$func$ LANGUAGE SQL;

-- Update recurring fine rules
UPDATE config.rule_recurring_fine SET grace_period=recurrence_interval;

-- Update Circulation Data
-- Only update if we were told to and the circ hasn't been checked in
UPDATE action.circulation SET grace_period=fine_interval WHERE :CircGrace AND (checkin_time IS NULL);

-- 0504
CREATE TABLE biblio.monograph_part (
    id              SERIAL  PRIMARY KEY,
    record          BIGINT  NOT NULL REFERENCES biblio.record_entry (id),
    label           TEXT    NOT NULL,
    label_sortkey   TEXT    NOT NULL,
    CONSTRAINT record_label_unique UNIQUE (record,label)
);

CREATE OR REPLACE FUNCTION biblio.normalize_biblio_monograph_part_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        evergreen.lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER norm_sort_label BEFORE INSERT OR UPDATE ON biblio.monograph_part FOR EACH ROW EXECUTE PROCEDURE biblio.normalize_biblio_monograph_part_sortkey();

CREATE TABLE asset.copy_part_map (
    id          SERIAL  PRIMARY KEY,
    target_copy BIGINT  NOT NULL, -- points o asset.copy
    part        INT     NOT NULL REFERENCES biblio.monograph_part (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX copy_part_map_cp_part_idx ON asset.copy_part_map (target_copy, part);

CREATE TABLE asset.call_number_prefix (
       id                      SERIAL   PRIMARY KEY,
       owning_lib          INT                 NOT NULL REFERENCES actor.org_unit (id),
       label               TEXT                NOT NULL, -- i18n
       label_sortkey   TEXT
);

CREATE OR REPLACE FUNCTION asset.normalize_affix_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        evergreen.lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER prefix_normalize_tgr BEFORE INSERT OR UPDATE ON asset.call_number_prefix FOR EACH ROW EXECUTE PROCEDURE asset.normalize_affix_sortkey();
CREATE UNIQUE INDEX asset_call_number_prefix_once_per_lib ON asset.call_number_prefix (label, owning_lib);
CREATE INDEX asset_call_number_prefix_sortkey_idx ON asset.call_number_prefix (label_sortkey);

CREATE TABLE asset.call_number_suffix (
       id                      SERIAL   PRIMARY KEY,
       owning_lib          INT                 NOT NULL REFERENCES actor.org_unit (id),
       label               TEXT                NOT NULL, -- i18n
       label_sortkey   TEXT
);
CREATE TRIGGER suffix_normalize_tgr BEFORE INSERT OR UPDATE ON asset.call_number_suffix FOR EACH ROW EXECUTE PROCEDURE asset.normalize_affix_sortkey();
CREATE UNIQUE INDEX asset_call_number_suffix_once_per_lib ON asset.call_number_suffix (label, owning_lib);
CREATE INDEX asset_call_number_suffix_sortkey_idx ON asset.call_number_suffix (label_sortkey);

INSERT INTO asset.call_number_suffix (id, owning_lib, label) VALUES (-1, 1, '');
INSERT INTO asset.call_number_prefix (id, owning_lib, label) VALUES (-1, 1, '');

DROP INDEX IF EXISTS asset.asset_call_number_label_once_per_lib;

ALTER TABLE asset.call_number
    ADD COLUMN prefix INT NOT NULL DEFAULT -1 REFERENCES asset.call_number_prefix(id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN suffix INT NOT NULL DEFAULT -1 REFERENCES asset.call_number_suffix(id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE auditor.asset_call_number_history
    ADD COLUMN prefix INT NOT NULL DEFAULT -1,
    ADD COLUMN suffix INT NOT NULL DEFAULT -1;

CREATE UNIQUE INDEX asset_call_number_label_once_per_lib ON asset.call_number (record, owning_lib, label, prefix, suffix) WHERE deleted = FALSE OR deleted IS FALSE;

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'ui.cat.volume_copy_editor.horizontal',
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.horizontal',
        'GUI: Horizontal layout for Volume/Copy Creator/Editor.',
        'coust', 'label'),
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.horizontal',
        'The main entry point for this interface is in Holdings Maintenance, Actions for Selected Rows, Edit Item Attributes / Call Numbers / Replace Barcodes.  This setting changes the top and bottom panes for that interface into left and right panes.',
	'coust', 'description'),
    'bool'
);



-- 0506
ALTER FUNCTION actor.org_unit_descendants( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_descendants( INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_descendants_distance( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_ancestors( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_ancestors_distance( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_full_path ( INT )  ROWS 2;
ALTER FUNCTION actor.org_unit_full_path ( INT, INT ) ROWS 2;
ALTER FUNCTION actor.org_unit_combined_ancestors ( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_common_ancestors ( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_ancestor_setting( TEXT, INT ) ROWS 1;
ALTER FUNCTION permission.grp_ancestors ( INT ) ROWS 1;
ALTER FUNCTION permission.grp_ancestors_distance( INT ) ROWS 1;
ALTER FUNCTION permission.grp_descendants_distance( INT ) ROWS 1;
ALTER FUNCTION permission.usr_perms ( INT ) ROWS 10;
ALTER FUNCTION permission.usr_has_perm_at_nd ( INT, TEXT) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at_all_nd ( INT, TEXT ) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at ( INT, TEXT ) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at_all ( INT, TEXT ) ROWS 1;


CREATE TRIGGER facet_force_nfc_tgr
    BEFORE UPDATE OR INSERT ON metabib.facet_entry
    FOR EACH ROW EXECUTE PROCEDURE evergreen.facet_force_nfc();

DROP FUNCTION IF EXISTS public.force_unicode_normal_form (TEXT,TEXT);
DROP FUNCTION IF EXISTS public.facet_force_nfc ();

DROP TRIGGER b_maintain_901 ON biblio.record_entry;
DROP TRIGGER b_maintain_901 ON authority.record_entry;
DROP TRIGGER b_maintain_901 ON serial.record_entry;

CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_901();

DROP FUNCTION IF EXISTS public.maintain_901 ();

------ Backporting note: 2.1+ only beyond here --------

CREATE SCHEMA unapi;

CREATE TABLE unapi.bre_output_layout (
    name                TEXT    PRIMARY KEY,
    transform           TEXT    REFERENCES config.xml_transform (name) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    mime_type           TEXT    NOT NULL,
    feed_top            TEXT    NOT NULL,
    holdings_element    TEXT,
    title_element       TEXT,
    description_element TEXT,
    creator_element     TEXT,
    update_ts_element   TEXT
);

INSERT INTO unapi.bre_output_layout
    (name,           transform, mime_type,              holdings_element, feed_top,         title_element, description_element, creator_element, update_ts_element)
        VALUES
    ('holdings_xml', NULL,      'application/xml',      NULL,             'hxml',           NULL,          NULL,                NULL,            NULL),
    ('marcxml',      'marcxml', 'application/marc+xml', 'record',         'collection',     NULL,          NULL,                NULL,            NULL),
    ('mods32',       'mods32',  'application/mods+xml', 'mods',           'modsCollection', NULL,          NULL,                NULL,            NULL)
;

-- Dummy functions, so we can create the real ones out of order
CREATE OR REPLACE FUNCTION unapi.aou    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acnp   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acns   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acn    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ssub   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sdist  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sstr   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sitem  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sunit  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sisum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sbsum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.sssum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.siss   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.auri   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acpn   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.acl    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ccs    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.bre    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.bmp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml ( bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.memoize (classname TEXT, obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
DECLARE
    key     TEXT;
    output  XML;
BEGIN
    key :=
        'id'        || COALESCE(obj_id::TEXT,'') ||
        'format'    || COALESCE(format::TEXT,'') ||
        'ename'     || COALESCE(ename::TEXT,'') ||
        'includes'  || COALESCE(includes::TEXT,'{}'::TEXT[]::TEXT) ||
        'org'       || COALESCE(org::TEXT,'') ||
        'depth'     || COALESCE(depth::TEXT,'') ||
        'slimit'    || COALESCE(slimit::TEXT,'') ||
        'soffset'   || COALESCE(soffset::TEXT,'') ||
        'include_xmlns'   || COALESCE(include_xmlns::TEXT,'');
    -- RAISE NOTICE 'memoize key: %', key;

    key := MD5(key);
    -- RAISE NOTICE 'memoize hash: %', key;

    -- XXX cache logic ... memcached? table?

    EXECUTE $$SELECT unapi.$$ || classname || $$( $1, $2, $3, $4, $5, $6, $7, $8, $9);$$ INTO output USING obj_id, format, ename, includes, org, depth, slimit, soffset, include_xmlns;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.bre(i, format, '', includes, org, depth, slimit, soffset, include_xmlns)) INTO tmp_xml FROM UNNEST( id_list ) i;

    IF layout.title_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title, include_xmlns;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description, include_xmlns;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator, include_xmlns;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts, include_xmlns;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', CASE WHEN $4 THEN XMLATTRIBUTES( $1 AS xmlns) ELSE NULL END, $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, include_xmlns;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.bre ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
DECLARE
    me      biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    tmp_xml TEXT;
    top_el  TEXT;
    output  XML;
    hxml    XML;
BEGIN

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.holdings_xml( obj_id, ouid, org, depth, includes, slimit, soffset, include_xmlns);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT * INTO me FROM biblio.record_entry WHERE id = obj_id;

    -- grab hodlings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN 
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, evergreen.array_remove_item_by_value(includes,'holdings_xml'), slimit, soffset, include_xmlns);
    ELSE
        hxml := NULL::XML;
    END IF;


    -- generate our item node


    IF format = 'marcxml' THEN
        tmp_xml := me.marc;
        IF tmp_xml !~ E'<marc:' THEN -- If we're not using the prefixed namespace in this record, then remove all declarations of it
           tmp_xml := REGEXP_REPLACE(tmp_xml, ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF; 
    ELSE
        tmp_xml := oils_xslt_process(me.marc, xfrm.xslt)::XML;
    END IF;

    top_el := REGEXP_REPLACE(tmp_xml, E'^.*?<((?:\\S+:)?' || layout.holdings_element || ').*$', E'\\1');

    IF hxml IS NOT NULL THEN -- XXX how do we configure the holdings position?
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('bre.unapi' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@bre/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_record_copy_count($2, $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT( name monograph_parts,
                            XMLAGG((SELECT unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE) FROM biblio.monograph_part WHERE record = $1))
                        )
                     ELSE NULL
                 END,
                 CASE WHEN ('acn' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name volumes,
                         (SELECT XMLAGG(acn) FROM (
                            SELECT  unapi.acn(acn.id,'xml','volume', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value('{acn,auri}'::TEXT[] || $5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE)
                              FROM  asset.call_number acn
                              WHERE acn.record = $1
                                    AND EXISTS (
                                        SELECT  1
                                          FROM  asset.copy acp
                                                JOIN actor.org_unit_descendants(
                                                    $2,
                                                    (COALESCE(
                                                        $4,
                                                        (SELECT aout.depth
                                                          FROM  actor.org_unit_type aout
                                                                JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.id = $2)
                                                        )
                                                    ))
                                                ) aoud ON (acp.circ_lib = aoud.id)
                                          LIMIT 1
                                    )
                              ORDER BY label_sortkey
                              LIMIT $6
                              OFFSET $7
                         )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('ssub' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ssub ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name subscription,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@ssub/' || id AS id,
                        start_date AS start, end_date AS end, expected_date_offset
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8),
                    XMLELEMENT( name distributions,
                        CASE 
                            WHEN ('sdist' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sdist( id, 'xml', 'distribution', evergreen.array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8, FALSE) FROM serial.distribution WHERE subscription = ssub.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.subscription ssub
          WHERE id = $1
          GROUP BY id, start_date, end_date, expected_date_offset, owning_lib;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sdist ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name distribution,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@sdist/' || id AS id,
			'tag:open-ils.org:U2@acn/' || receive_call_number AS receive_call_number,
			'tag:open-ils.org:U2@acn/' || bind_call_number AS bind_call_number,
                        unit_label_prefix, label, unit_label_suffix, summary_method
                    ),
                    unapi.aou( holding_lib, $2, 'holding_lib', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8),
                    CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name streams,
                        CASE 
                            WHEN ('sstr' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sstr( id, 'xml', 'stream', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.stream WHERE distribution = sdist.id))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name summaries,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sbsum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.basic_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sisum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.index_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('ssum' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.sssum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE) FROM serial.supplement_summary WHERE distribution = sdist.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.distribution sdist
          WHERE id = $1
          GROUP BY id, label, unit_label_prefix, unit_label_suffix, holding_lib, summary_method, subscription, receive_call_number, bind_call_number;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sstr ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name stream,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sstr/' || id AS id,
                    routing_label
                ),
                CASE WHEN distribution IS NOT NULL AND ('sdist' = ANY ($4)) THEN unapi.sssum( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                XMLELEMENT( name items,
                    CASE 
                        WHEN ('sitem' = ANY ($4)) THEN
                            XMLAGG((SELECT unapi.sitem( id, 'xml', 'serial_item', evergreen.array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8, FALSE) FROM serial.item WHERE stream = sstr.id))
                        ELSE NULL
                    END
                )
            )
      FROM  serial.stream sstr
      WHERE id = $1
      GROUP BY id, routing_label, distribution;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.siss ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name issuance,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@siss/' || id AS id,
                    create_date, edit_date, label, date_published,
                    holding_code, holding_type, holding_link_id
                ),
                CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', evergreen.array_remove_item_by_value($4,'siss'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                XMLELEMENT( name items,
                    CASE 
                        WHEN ('sitem' = ANY ($4)) THEN
                            XMLAGG((SELECT unapi.sitem( id, 'xml', 'serial_item', evergreen.array_remove_item_by_value($4,'siss'), $5, $6, $7, $8, FALSE) FROM serial.item WHERE issuance = sstr.id))
                        ELSE NULL
                    END
                )
            )
      FROM  serial.issuance sstr
      WHERE id = $1
      GROUP BY id, create_date, edit_date, label, date_published, holding_code, holding_type, holding_link_id, subscription;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sitem ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_item,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@sitem/' || id AS id,
                        'tag:open-ils.org:U2@siss/' || issuance AS issuance,
                        date_expected, date_received
                    ),
                    CASE WHEN issuance IS NOT NULL AND ('siss' = ANY ($4)) THEN unapi.siss( issuance, $2, 'issuance', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN stream IS NOT NULL AND ('sstr' = ANY ($4)) THEN unapi.sstr( stream, $2, 'stream', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN unit IS NOT NULL AND ('sunit' = ANY ($4)) THEN unapi.sunit( stream, $2, 'serial_unit', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN uri IS NOT NULL AND ('auri' = ANY ($4)) THEN unapi.auri( uri, $2, 'uri', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END
--                    XMLELEMENT( name notes,
--                        CASE 
--                            WHEN ('acpn' = ANY ($4)) THEN
--                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
--                            ELSE NULL
--                        END
--                    )
                )
          FROM  serial.item sitem
          WHERE id = $1;
$F$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION unapi.sssum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sssum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.supplement_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sbsum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sbsum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.basic_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sisum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name serial_summary,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sbsum/' || id AS id,
                    'sisum' AS type, generated_coverage, textual_holdings, show_generated
                ),
                CASE WHEN ('sdist' = ANY ($4)) THEN unapi.sdist( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'ssum'), $5, $6, $7, $8, FALSE) ELSE NULL END
            )
      FROM  serial.index_summary ssum
      WHERE id = $1
      GROUP BY id, generated_coverage, textual_holdings, distribution, show_generated;
$F$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION unapi.aou ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
DECLARE
    output XML;
BEGIN
    IF ename = 'circlib' THEN
        SELECT  XMLELEMENT(
                    name circlib,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/actors/v1' AS xmlns,
                        id AS ident
                    ),
                    name
                ) INTO output
          FROM  actor.org_unit aou
          WHERE id = obj_id;
    ELSE
        EXECUTE $$SELECT  XMLELEMENT(
                    name $$ || ename || $$,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/actors/v1' AS xmlns,
                        'tag:open-ils.org:U2@aou/' || id AS id,
                        shortname, name, opac_visible
                    )
                )
          FROM  actor.org_unit aou
         WHERE id = $1 $$ INTO output USING obj_id;
    END IF;

    RETURN output;

END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.acl ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name location,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident
                ),
                name
            )
      FROM  asset.copy_location
      WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ccs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name status,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident
                ),
                name
            )
      FROM  config.copy_status
      WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acpn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy_note,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        create_date AS date,
                        title
                    ),
                    value
                )
          FROM  asset.copy_note
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name statcat,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        sc.name,
                        sc.opac_visible
                    ),
                    asce.value
                )
          FROM  asset.stat_cat_entry asce
                JOIN asset.stat_cat sc ON (sc.id = asce.stat_cat)
          WHERE asce.id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.bmp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name monograph_part,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@bmp/' || id AS id,
                        id AS ident,
                        label,
                        label_sortkey,
                        'tag:open-ils.org:U2@bre/' || record AS record
                    ),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            XMLELEMENT( name copies,
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy cp
                                            JOIN asset.copy_part_map cpm ON (cpm.target_copy = cp.id)
                                      WHERE cpm.part = $1
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT $7
                                      OFFSET $8
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8, FALSE) ELSE NULL END
                )
          FROM  biblio.monograph_part
          WHERE id = $1
          GROUP BY id, label, label_sortkey, record;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.ascecm( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    ),
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                XMLAGG((SELECT unapi.bmp( part, 'xml', 'monograph_part', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_part_map WHERE target_copy = cp.id))
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
          GROUP BY id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.sunit ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_unit,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, status_changed_time,
                        floating, mint_condition, detailed_contents, sort_key, summary_contents, cost 
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.unit cp
          WHERE id = $1
          GROUP BY  id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, floating, mint_condition,
                    deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible, status_changed_time, detailed_contents, sort_key, summary_contents, cost;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acp' = ANY ($4)) THEN
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy cp
                                            JOIN actor.org_unit_descendants(
                                                (SELECT id FROM actor.org_unit WHERE shortname = $5),
                                                (COALESCE($6,(SELECT aout.depth FROM actor.org_unit_type aout JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.shortname = $5))))
                                            ) aoud ON (cp.circ_lib = aoud.id)
                                      WHERE cp.call_number = acn.id
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT $7
                                      OFFSET $8
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT(
                        name uris,
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    CASE WHEN ('acnp' = ANY ($4)) THEN unapi.acnp( acn.prefix, 'marcxml', 'prefix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN ('acns' = ANY ($4)) THEN unapi.acns( acn.suffix, 'marcxml', 'suffix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acnp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_prefix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        label_sortkey
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acnp'), $5, $6, $7, $8)
                )
          FROM  asset.call_number_prefix
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acns ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_suffix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        label_sortkey
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acns'), $5, $6, $7, $8)
                )
          FROM  asset.call_number_suffix
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.auri ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@auri/' || uri.id AS id,
                        use_restriction,
                        href,
                        label
                    ),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acn' = ANY ($4)) THEN
                                (SELECT XMLAGG(acn) FROM (SELECT unapi.acn( call_number, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'auri'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE uri = uri.id)x)
                            ELSE NULL
                        END
                    )
                ) AS x
          FROM  asset.uri uri
          WHERE uri.id = $1
          GROUP BY uri.id, use_restriction, href, label;
$F$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS public.array_remove_item_by_value(ANYARRAY,ANYELEMENT);

DROP FUNCTION IF EXISTS public.lpad_number_substrings(TEXT,TEXT,INT);


-- 0511
CREATE OR REPLACE FUNCTION evergreen.fake_fkey_tgr () RETURNS TRIGGER AS $F$
DECLARE
    copy_id BIGINT;
BEGIN
    EXECUTE 'SELECT ($1).' || quote_ident(TG_ARGV[0]) INTO copy_id USING NEW;
    PERFORM * FROM asset.copy WHERE id = copy_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Key (%.%=%) does not exist in asset.copy', TG_TABLE_SCHEMA, TG_TABLE_NAME, copy_id;
    END IF;
    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;

CREATE TRIGGER action_circulation_target_copy_trig AFTER INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('target_copy');

-- 0512
CREATE TABLE biblio.peer_type (
    id      SERIAL  PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE -- i18n
);

CREATE TABLE biblio.peer_bib_copy_map (
    id      SERIAL  PRIMARY KEY,
    peer_type   INT     NOT NULL REFERENCES biblio.peer_type (id),
    peer_record BIGINT      NOT NULL REFERENCES biblio.record_entry (id),
    target_copy BIGINT      NOT NULL -- can't use fkey because of acp subtables
);
CREATE INDEX peer_bib_copy_map_record_idx ON biblio.peer_bib_copy_map (peer_record);
CREATE INDEX peer_bib_copy_map_copy_idx ON biblio.peer_bib_copy_map (target_copy);

DROP TABLE asset.opac_visible_copies;
CREATE TABLE asset.opac_visible_copies (
  id        BIGSERIAL primary key,
  copy_id   BIGINT,
  record    BIGINT,
  circ_lib  INTEGER
);

INSERT INTO biblio.peer_type (id,name) VALUES
    (1,oils_i18n_gettext(1,'Bound Volume','bpt','name')),
    (2,oils_i18n_gettext(2,'Bilingual','bpt','name')),
    (3,oils_i18n_gettext(3,'Back-to-back','bpt','name')),
    (4,oils_i18n_gettext(4,'Set','bpt','name')),
    (5,oils_i18n_gettext(5,'e-Reader Preload','bpt','name')); 

SELECT SETVAL('biblio.peer_type_id_seq'::TEXT, 100);

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        PERFORM 1
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                JOIN asset.uri uri ON (map.uri = uri.id)
          WHERE NOT cn.deleted
                AND cn.label = '##URI##'
                AND uri.active
                AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
          LIMIT 1;

        IF FOUND THEN
            -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.opac_visible_copies
              WHERE circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                  WHERE cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  asset.call_number cn
                      WHERE cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                      LIMIT 1;

                    IF FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_record_copy_count($2, $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT( name monograph_parts,
                            XMLAGG((SELECT unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE) FROM biblio.monograph_part WHERE record = $1))
                        )
                     ELSE NULL
                 END,
                 CASE WHEN ('acn' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN
                     XMLELEMENT(
                         name volumes,
                         (SELECT XMLAGG(acn) FROM (
                            SELECT  unapi.acn(acn.id,'xml','volume',evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value('{acn,auri}'::TEXT[] || $5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE)
                              FROM  asset.call_number acn
                              WHERE acn.record = $1
                                    AND EXISTS (
                                        SELECT  1
                                          FROM  asset.copy acp
                                                JOIN actor.org_unit_descendants(
                                                    $2,
                                                    (COALESCE(
                                                        $4,
                                                        (SELECT aout.depth
                                                          FROM  actor.org_unit_type aout
                                                                JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.id = $2)
                                                        )
                                                    ))
                                                ) aoud ON (acp.circ_lib = aoud.id)
                                          LIMIT 1
                                    )
                              ORDER BY label_sortkey
                              LIMIT $6
                              OFFSET $7
                         )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('ssub' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('acp' = ANY ($5)) THEN
                     XMLELEMENT(
                         name foreign_copies,
                         (SELECT XMLAGG(acp) FROM (
                            SELECT  unapi.acp(p.target_copy,'xml','copy','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND peer_record = $1
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.ascecm( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name foreign_records,
                        CASE
                            WHEN ('bre' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE) FROM biblio.peer_bib_copy_map WHERE target_copy = cp.id))
                            ELSE NULL
                        END

                    ),
                    CASE
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                XMLAGG((SELECT unapi.bmp( part, 'xml', 'monograph_part', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_part_map WHERE target_copy = cp.id))
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
          GROUP BY id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION asset.refresh_opac_visible_copies_mat_view () RETURNS VOID AS $$

    TRUNCATE TABLE asset.opac_visible_copies;

    INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
    SELECT  cp.id, cp.circ_lib, cn.record
    FROM  asset.copy cp
        JOIN asset.call_number cn ON (cn.id = cp.call_number)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
        JOIN biblio.record_entry b ON (cn.record = b.id)
    WHERE NOT cp.deleted
        AND NOT cn.deleted
        AND NOT b.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible
            UNION
    SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record
    FROM  asset.copy cp
        JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
    WHERE NOT cp.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible;

$$ LANGUAGE SQL;
COMMENT ON FUNCTION asset.refresh_opac_visible_copies_mat_view() IS $$
Rebuild the copy OPAC visibility cache.  Useful during migrations.
$$;

SELECT asset.refresh_opac_visible_copies_mat_view();
CREATE INDEX opac_visible_copies_idx1 on asset.opac_visible_copies (record, circ_lib);
CREATE INDEX opac_visible_copies_copy_id_idx on asset.opac_visible_copies (copy_id);
CREATE UNIQUE INDEX opac_visible_copies_once_per_record_idx on asset.opac_visible_copies (copy_id, record);
 
CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    add_query       TEXT;
    remove_query    TEXT;
    do_add          BOOLEAN := false;
    do_remove       BOOLEAN := false;
BEGIN
    add_query := $$
            INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
              SELECT id, circ_lib, record FROM (
                SELECT  cp.id, cp.circ_lib, cn.record, cn.id AS call_number
                  FROM  asset.copy cp
                        JOIN asset.call_number cn ON (cn.id = cp.call_number)
                        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                        JOIN asset.copy_location cl ON (cp.location = cl.id)
                        JOIN config.copy_status cs ON (cp.status = cs.id)
                        JOIN biblio.record_entry b ON (cn.record = b.id)
                  WHERE NOT cp.deleted
                        AND NOT cn.deleted
                        AND NOT b.deleted
                        AND cs.opac_visible
                        AND cl.opac_visible
                        AND cp.opac_visible
                        AND a.opac_visible
                            UNION
                SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record, NULL AS call_number
                  FROM  asset.copy cp
                        JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
                        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                        JOIN asset.copy_location cl ON (cp.location = cl.id)
                        JOIN config.copy_status cs ON (cp.status = cs.id)
                  WHERE NOT cp.deleted
                        AND cs.opac_visible
                        AND cl.opac_visible
                        AND cp.opac_visible
                        AND a.opac_visible
                    ) AS x 

    $$;
 
    remove_query := $$ DELETE FROM asset.opac_visible_copies WHERE copy_id IN ( SELECT id FROM asset.copy WHERE $$;

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN
        IF TG_OP = 'INSERT' THEN
            add_query := add_query || 'WHERE x.id = ' || NEW.target_copy || ' AND x.record = ' || NEW.peer_record || ';';
            EXECUTE add_query;
            RETURN NEW;
        ELSE
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE copy_id = ' || OLD.target_copy || ' AND record = ' || OLD.peer_record || ';';
            EXECUTE remove_query;
            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            add_query := add_query || 'WHERE x.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN

        IF OLD.location    <> NEW.location OR
           OLD.call_number <> NEW.call_number OR
           OLD.status      <> NEW.status OR
           OLD.circ_lib    <> NEW.circ_lib THEN
            -- any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly
            do_remove := true;
            do_add := true;
        ELSE

            IF OLD.deleted <> NEW.deleted THEN
                IF NEW.deleted THEN
                    do_remove := true;
                ELSE
                    do_add := true;
                END IF;
            END IF;

            IF OLD.opac_visible <> NEW.opac_visible THEN
                IF OLD.opac_visible THEN
                    do_remove := true;
                ELSIF NOT do_remove THEN -- handle edge case where deleted item
                                        -- is also marked opac_visible
                    do_add := true;
                END IF;
            END IF;

        END IF;

        IF do_remove THEN
            DELETE FROM asset.opac_visible_copies WHERE copy_id = NEW.id;
        END IF;
        IF do_add THEN
            add_query := add_query || 'WHERE x.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('call_number', 'record_entry') THEN -- these have a 'deleted' column
 
        IF OLD.deleted AND NEW.deleted THEN -- do nothing

            RETURN NEW;
 
        ELSIF NEW.deleted THEN -- remove rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                DELETE FROM asset.opac_visible_copies WHERE copy_id IN (SELECT id FROM asset.copy WHERE call_number = NEW.id);
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                DELETE FROM asset.opac_visible_copies WHERE record = NEW.id;
            END IF;
 
            RETURN NEW;
 
        ELSIF OLD.deleted THEN -- add rows
 
            IF TG_TABLE_NAME IN ('copy','unit') THEN
                add_query := add_query || 'WHERE x.id = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'call_number' THEN
                add_query := add_query || 'WHERE x.call_number = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                add_query := add_query || 'WHERE x.record = ' || NEW.id || ';';
            END IF;
 
            EXECUTE add_query;
            RETURN NEW;
 
        END IF;
 
    END IF;

    IF TG_TABLE_NAME = 'call_number' THEN

        IF OLD.record <> NEW.record THEN
            -- call number is linked to different bib
            remove_query := remove_query || 'call_number = ' || NEW.id || ');';
            EXECUTE remove_query;
            add_query := add_query || 'WHERE x.call_number = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('record_entry') THEN
        RETURN NEW; -- don't have 'opac_visible'
    END IF;

    -- actor.org_unit, asset.copy_location, asset.copy_status
    IF NEW.opac_visible = OLD.opac_visible THEN -- do nothing

        RETURN NEW;

    ELSIF NEW.opac_visible THEN -- add rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            add_query := add_query || 'AND cp.circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            add_query := add_query || 'AND cp.location = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            add_query := add_query || 'AND cp.status = ' || NEW.id || ';';
        END IF;
 
        EXECUTE add_query;
 
    ELSE -- delete rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            remove_query := remove_query || 'location = ' || NEW.id || ');';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            remove_query := remove_query || 'status = ' || NEW.id || ');';
        END IF;
 
        EXECUTE remove_query;
 
    END IF;
 
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;
COMMENT ON FUNCTION asset.cache_copy_visibility() IS $$
Trigger function to update the copy OPAC visiblity cache.
$$;

CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR DELETE ON biblio.peer_bib_copy_map FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM metabib.record_attr WHERE id = NEW.id; -- Kill the attrs hash, useless on deleted records
        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  value::TEXT INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id)
                      WHERE subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( attr_value ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = attrs || new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

-- 0513
CREATE OR REPLACE FUNCTION unapi.mra ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name attributes,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@mra/' || mra.id AS id,
                        'tag:open-ils.org:U2@bre/' || mra.id AS record
                    ),
                    (SELECT XMLAGG(foo.y)
                      FROM (SELECT XMLELEMENT(
                                name field,
                                XMLATTRIBUTES(
                                    key AS name,
                                    cvm.value AS "coded-value",
                                    rad.filter,
                                    rad.sorter
                                ),
                                x.value
                            )
                           FROM EACH(mra.attrs) AS x
                                JOIN config.record_attr_definition rad ON (x.key = rad.name)
                                LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = x.key AND code = x.value)
                        )foo(y)
                    )
                )
          FROM  metabib.record_attr mra
          WHERE mra.id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.bre ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
DECLARE
    me      biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    tmp_xml TEXT;
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
BEGIN

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.holdings_xml( obj_id, ouid, org, depth, includes, slimit, soffset, include_xmlns);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT * INTO me FROM biblio.record_entry WHERE id = obj_id;

    -- grab SVF if we need them
    IF ('mra' = ANY (includes)) THEN
        axml := unapi.mra(obj_id,NULL,NULL,NULL,NULL);
    ELSE
        axml := NULL::XML;
    END IF;

    -- grab hodlings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, evergreen.array_remove_item_by_value(includes,'holdings_xml'), slimit, soffset, include_xmlns);
    ELSE
        hxml := NULL::XML;
    END IF;


    -- generate our item node


    IF format = 'marcxml' THEN
        tmp_xml := me.marc;
        IF tmp_xml !~ E'<marc:' THEN -- If we're not using the prefixed namespace in this record, then remove all declarations of it
           tmp_xml := REGEXP_REPLACE(tmp_xml, ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF;
    ELSE
        tmp_xml := oils_xslt_process(me.marc, xfrm.xslt)::XML;
    END IF;

    top_el := REGEXP_REPLACE(tmp_xml, E'^.*?<((?:\\S+:)?' || layout.holdings_element || ').*$', E'\\1');

    IF axml IS NOT NULL THEN
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

    IF hxml IS NOT NULL THEN -- XXX how do we configure the holdings position?
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('bre.unapi' = ANY (includes)) THEN
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@bre/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;


-- 0514
CREATE OR REPLACE FUNCTION unapi.bre ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
DECLARE
    me      biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    tmp_xml TEXT;
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
BEGIN

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.holdings_xml( obj_id, ouid, org, depth, includes, slimit, soffset, include_xmlns);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT * INTO me FROM biblio.record_entry WHERE id = obj_id;

    -- grab SVF if we need them
    IF ('mra' = ANY (includes)) THEN
        axml := unapi.mra(obj_id,NULL,NULL,NULL,NULL);
    ELSE
        axml := NULL::XML;
    END IF;

    -- grab hodlings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, evergreen.array_remove_item_by_value(includes,'holdings_xml'), slimit, soffset, include_xmlns);
    ELSE
        hxml := NULL::XML;
    END IF;


    -- generate our item node


    IF format = 'marcxml' THEN
        tmp_xml := me.marc;
        IF tmp_xml !~ E'<marc:' THEN -- If we're not using the prefixed namespace in this record, then remove all declarations of it
           tmp_xml := REGEXP_REPLACE(tmp_xml, ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF;
    ELSE
        tmp_xml := oils_xslt_process(me.marc, xfrm.xslt)::XML;
    END IF;

    top_el := REGEXP_REPLACE(tmp_xml, E'^.*?<((?:\\S+:)?' || layout.holdings_element || ').*$', E'\\1');

    IF axml IS NOT NULL THEN
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

    IF hxml IS NOT NULL THEN -- XXX how do we configure the holdings position?
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('bre.unapi' = ANY (includes)) THEN
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@bre/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    output := REGEXP_REPLACE(output::TEXT,E'>\\s+<','><','gs')::XML;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL;



-- 0516
CREATE OR REPLACE FUNCTION public.extract_acq_marc_field ( BIGINT, TEXT, TEXT) RETURNS TEXT AS $$    
    SELECT extract_marc_field('acq.lineitem', $1, $2, $3);
$$ LANGUAGE SQL;

-- 0518
CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field( marc TEXT, ff TEXT ) RETURNS TEXT AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        IF ff_pos.tag = 'ldr' THEN
            val := oils_xpath_string('//*[local-name()="leader"]', marc);
            IF val IS NOT NULL THEN
                val := SUBSTRING( val, ff_pos.start_pos + 1, ff_pos.length );
                RETURN val;
            END IF;
        ELSE 
            FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
                val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
                RETURN val;
            END LOOP;
        END IF;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        RETURN val;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;


-- 0519
CREATE OR REPLACE FUNCTION vandelay.marc21_extract_all_fixed_fields( marc TEXT ) RETURNS SETOF biblio.record_ff_map AS $func$
DECLARE
    tag_data    TEXT;
    rtype       TEXT;
    ff_pos      RECORD;
    output      biblio.record_ff_map%ROWTYPE;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;

    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE rec_type = rtype ORDER BY tag DESC LOOP
        output.ff_name  := ff_pos.fixed_field;
        output.ff_value := NULL;

        IF ff_pos.tag = 'ldr' THEN
            output.ff_value := oils_xpath_string('//*[local-name()="leader"]', marc);
            IF output.ff_value IS NOT NULL THEN
                output.ff_value := SUBSTRING( output.ff_value, ff_pos.start_pos + 1, ff_pos.length );
                RETURN NEXT output;
                output.ff_value := NULL;
            END IF;
        ELSE
            FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
                output.ff_value := SUBSTRING( tag_data, ff_pos.start_pos + 1, ff_pos.length );
                IF output.ff_value IS NULL THEN output.ff_value := REPEAT( ff_pos.default_val, ff_pos.length ); END IF;
                RETURN NEXT output;
                output.ff_value := NULL;
            END LOOP;
        END IF;
    
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;


-- 0521
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
BEGIN

    -- Clear any URI mappings and call numbers for this bib.
    -- This leads to acn / auricnm inflation, but also enables
    -- old acn/auricnm's to go away and for bibs to be deleted.
    FOR uri_cn_id IN SELECT id FROM asset.call_number WHERE record = bib_id AND label = '##URI##' AND NOT deleted LOOP
        DELETE FROM asset.uri_call_number_map WHERE call_number = uri_cn_id;
        DELETE FROM asset.call_number WHERE id = uri_cn_id;
    END LOOP;

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()|//*[@code="u"]/text()',uri_xml))[1];
            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()',uri_xml))[1];
            CONTINUE WHEN uri_href IS NULL OR uri_label IS NULL;

            -- Get the distinct list of libraries wanting to use 
            SELECT  ARRAY_ACCUM(
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
                SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                IF NOT FOUND THEN -- create one
                    INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                    IF uri_use IS NULL THEN
                        SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction IS NULL AND active;
                    ELSE
                        SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
                    END IF;
                END IF;

                FOR j IN 1 .. ARRAY_UPPER(uri_owner_list, 1) LOOP
                    uri_owner := uri_owner_list[j];

                    SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
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
                    END IF;

                END LOOP;

            END IF;

        END LOOP;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;


-- 0522
UPDATE config.org_unit_setting_type SET datatype = 'string' WHERE name = 'ui.general.button_bar';

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype) VALUES ('ui.general.hotkeyset', 'GUI: Default Hotkeyset', 'Default Hotkeyset for clients (filename without the .keyset).  Examples: Default, Minimal, and None', 'string');

UPDATE actor.org_unit_setting SET value='"circ"' WHERE name = 'ui.general.button_bar' AND value='true';

UPDATE actor.org_unit_setting SET value='"none"' WHERE name = 'ui.general.button_bar' AND value='false';


-- 0523
INSERT into config.org_unit_setting_type
( name, label, description, datatype, fm_class ) VALUES
( 'cat.default_copy_status_fast',
  oils_i18n_gettext( 'cat.default_copy_status_fast', 'Cataloging: Default copy status (fast add)', 'coust', 'label'),
  oils_i18n_gettext( 'cat.default_copy_status_fast', 'Default status when a copy is created using the "Fast Add" interface.', 'coust', 'description'),
  'link', 'ccs'
);

INSERT into config.org_unit_setting_type
( name, label, description, datatype, fm_class ) VALUES
( 'cat.default_copy_status_normal',
  oils_i18n_gettext( 'cat.default_copy_status_normal', 'Cataloging: Default copy status (normal)', 'coust', 'label'),
  oils_i18n_gettext( 'cat.default_copy_status_normal', 'Default status when a copy is created using the normal volume/copy creator interface.', 'coust', 'description'),
  'link', 'ccs'
);

-- 0524
INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'ui.unified_volume_copy_editor',
  oils_i18n_gettext( 'ui.unified_volume_copy_editor', 'GUI: Unified Volume/Item Creator/Editor', 'coust', 'label'),
  oils_i18n_gettext( 'ui.unified_volume_copy_editor', 'If true combines the Volume/Copy Creator and Item Attribute Editor in some instances.', 'coust', 'description'),
  'bool'
);

-- 0525
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM metabib.record_attr WHERE id = NEW.id; -- Kill the attrs hash, useless on deleted records
        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  m.value INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id) v
                            JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
                      WHERE v.subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( attr_value ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = attrs || new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

ALTER TABLE config.circ_matrix_weights ADD COLUMN marc_bib_level NUMERIC(6,2) NOT NULL DEFAULT 0.0;

UPDATE config.circ_matrix_weights
SET marc_bib_level = marc_vr_format;

ALTER TABLE config.hold_matrix_weights ADD COLUMN marc_bib_level NUMERIC(6, 2) NOT NULL DEFAULT 0.0;

UPDATE config.hold_matrix_weights
SET marc_bib_level = marc_vr_format;

ALTER TABLE config.circ_matrix_weights ALTER COLUMN marc_bib_level DROP DEFAULT;

ALTER TABLE config.hold_matrix_weights ALTER COLUMN marc_bib_level DROP DEFAULT;

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN marc_bib_level text;

ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN marc_bib_level text;

CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, item_object asset.copy, user_object actor.usr, renewal BOOL ) RETURNS action.found_circ_matrix_matchpoint AS $func$
DECLARE
    cn_object       asset.call_number%ROWTYPE;
    rec_descriptor  metabib.rec_descriptor%ROWTYPE;
    cur_matchpoint  config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint      config.circ_matrix_matchpoint%ROWTYPE;
    weights         config.circ_matrix_weights%ROWTYPE;
    user_age        INTERVAL;
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
        weights.circ_modifier       := 5.0;
        weights.marc_type           := 4.0;
        weights.marc_form           := 3.0;
        weights.marc_bib_level      := 2.0;
        weights.marc_vr_format      := 2.0;
        weights.copy_circ_lib       := 8.0;
        weights.copy_owning_lib     := 8.0;
        weights.user_home_ou        := 8.0;
        weights.ref_flag            := 1.0;
        weights.juvenile_flag       := 6.0;
        weights.is_renewal          := 7.0;
        weights.usr_age_lower_bound := 0.0;
        weights.usr_age_upper_bound := 0.0;
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
          WHERE m.active
                -- Permission Groups
             -- AND (m.grp                      IS NULL OR upgad.id IS NOT NULL) -- Optional Permission Group?
                -- Org Units
             -- AND (m.org_unit                 IS NULL OR ctoua.id IS NOT NULL) -- Optional Org Unit?
                AND (m.copy_owning_lib          IS NULL OR cnoua.id IS NOT NULL)
                AND (m.copy_circ_lib            IS NULL OR iooua.id IS NOT NULL)
                AND (m.user_home_ou             IS NULL OR uhoua.id IS NOT NULL)
                -- Circ Type
                AND (m.is_renewal               IS NULL OR m.is_renewal = renewal)
                -- Static User Checks
                AND (m.juvenile_flag            IS NULL OR m.juvenile_flag = user_object.juvenile)
                AND (m.usr_age_lower_bound      IS NULL OR (user_age IS NOT NULL AND m.usr_age_lower_bound < user_age))
                AND (m.usr_age_upper_bound      IS NULL OR (user_age IS NOT NULL AND m.usr_age_upper_bound > user_age))
                -- Static Item Checks
                AND (m.circ_modifier            IS NULL OR m.circ_modifier = item_object.circ_modifier)
                AND (m.marc_type                IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
                AND (m.marc_form                IS NULL OR m.marc_form = rec_descriptor.item_form)
                AND (m.marc_bib_level           IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
                AND (m.marc_vr_format           IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
                AND (m.ref_flag                 IS NULL OR m.ref_flag = item_object.ref)
          ORDER BY
                -- Permission Groups
                CASE WHEN upgad.distance        IS NOT NULL THEN 2^(2*weights.grp - (upgad.distance/denominator)) ELSE 0.0 END +
                -- Org Units
                CASE WHEN ctoua.distance        IS NOT NULL THEN 2^(2*weights.org_unit - (ctoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN cnoua.distance        IS NOT NULL THEN 2^(2*weights.copy_owning_lib - (cnoua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN iooua.distance        IS NOT NULL THEN 2^(2*weights.copy_circ_lib - (iooua.distance/denominator)) ELSE 0.0 END +
                CASE WHEN uhoua.distance        IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
                -- Circ Type                    -- Note: 4^x is equiv to 2^(2*x)
                CASE WHEN m.is_renewal          IS NOT NULL THEN 4^weights.is_renewal ELSE 0.0 END +
                -- Static User Checks
                CASE WHEN m.juvenile_flag       IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
                CASE WHEN m.usr_age_lower_bound IS NOT NULL THEN 4^weights.usr_age_lower_bound ELSE 0.0 END +
                CASE WHEN m.usr_age_upper_bound IS NOT NULL THEN 4^weights.usr_age_upper_bound ELSE 0.0 END +
                -- Static Item Checks
                CASE WHEN m.circ_modifier       IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
                CASE WHEN m.marc_type           IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
                CASE WHEN m.marc_form           IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
                CASE WHEN m.marc_vr_format      IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
                CASE WHEN m.ref_flag            IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END DESC,
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
    rec_descriptor      metabib.rec_descriptor%ROWTYPE;
    matchpoint          config.hold_matrix_matchpoint%ROWTYPE;
    weights             config.hold_matrix_weights%ROWTYPE;
    denominator         NUMERIC(6,2);
BEGIN
    SELECT INTO user_object         * FROM actor.usr                WHERE id = match_user;
    SELECT INTO requestor_object    * FROM actor.usr                WHERE id = match_requestor;
    SELECT INTO item_object         * FROM asset.copy               WHERE id = match_item;
    SELECT INTO item_cn_object      * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor      * FROM metabib.rec_descriptor   WHERE record = item_cn_object.record;

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
               JOIN actor.org_unit_ancestors_distance( cn_object.owning_lib ) d ON (wa.org_unit = d.id)
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
        weights.usr_grp         := 7.0;
        weights.requestor_grp   := 8.0;
        weights.circ_modifier   := 4.0;
        weights.marc_type       := 3.0;
        weights.marc_form       := 2.0;
        weights.marc_bib_level  := 1.0;
        weights.marc_vr_format  := 1.0;
        weights.juvenile_flag   := 4.0;
        weights.ref_flag        := 0.0;
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
            LEFT JOIN actor.org_unit_ancestors_distance( pickup_ou ) puoua ON m.pickup_ou = puoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( request_ou ) rqoua ON m.request_ou = rqoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) cnoua ON m.item_owning_ou = cnoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.item_circ_ou = iooua.id
            LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
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
            -- Static User Checks
            AND (m.juvenile_flag        IS NULL OR m.juvenile_flag = user_object.juvenile)
            -- Static Item Checks
            AND (m.circ_modifier        IS NULL OR m.circ_modifier = item_object.circ_modifier)
            AND (m.marc_type            IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
            AND (m.marc_form            IS NULL OR m.marc_form = rec_descriptor.item_form)
            AND (m.marc_bib_level       IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
            AND (m.marc_vr_format       IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
            AND (m.ref_flag             IS NULL OR m.ref_flag = item_object.ref)
      ORDER BY
            -- Permission Groups
            CASE WHEN rpgad.distance    IS NOT NULL THEN 2^(2*weights.requestor_grp - (rpgad.distance/denominator)) ELSE 0.0 END +
            CASE WHEN upgad.distance    IS NOT NULL THEN 2^(2*weights.usr_grp - (upgad.distance/denominator)) ELSE 0.0 END +
            -- Org Units
            CASE WHEN puoua.distance    IS NOT NULL THEN 2^(2*weights.pickup_ou - (puoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN rqoua.distance    IS NOT NULL THEN 2^(2*weights.request_ou - (rqoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN cnoua.distance    IS NOT NULL THEN 2^(2*weights.item_owning_ou - (cnoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN iooua.distance    IS NOT NULL THEN 2^(2*weights.item_circ_ou - (iooua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN uhoua.distance    IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
            -- Static User Checks       -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.juvenile_flag   IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier   IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
            CASE WHEN m.marc_type       IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
            CASE WHEN m.marc_form       IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
            CASE WHEN m.marc_vr_format  IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
            CASE WHEN m.ref_flag        IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return just the ID for now
    RETURN matchpoint.id;
END;
$func$ LANGUAGE 'plpgsql';

-- 0528
CREATE OR REPLACE FUNCTION maintain_control_numbers() RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $record = MARC::Record->new_from_xml($_TD->{new}{marc});
my $schema = $_TD->{table_schema};
my $rec_id = $_TD->{new}{id};

# Short-circuit if maintaining control numbers per MARC21 spec is not enabled
my $enable = spi_exec_query("SELECT enabled FROM config.global_flag WHERE name = 'cat.maintain_control_numbers'");
if (!($enable->{processed}) or $enable->{rows}[0]->{enabled} eq 'f') {
    return;
}

# Get the control number identifier from an OU setting based on $_TD->{new}{owner}
my $ou_cni = 'EVRGRN';

my $owner;
if ($schema eq 'serial') {
    $owner = $_TD->{new}{owning_lib};
} else {
    # are.owner and bre.owner can be null, so fall back to the consortial setting
    $owner = $_TD->{new}{owner} || 1;
}

my $ous_rv = spi_exec_query("SELECT value FROM actor.org_unit_ancestor_setting('cat.marc_control_number_identifier', $owner)");
if ($ous_rv->{processed}) {
    $ou_cni = $ous_rv->{rows}[0]->{value};
    $ou_cni =~ s/"//g; # Stupid VIM syntax highlighting"
} else {
    # Fall back to the shortname of the OU if there was no OU setting
    $ous_rv = spi_exec_query("SELECT shortname FROM actor.org_unit WHERE id = $owner");
    if ($ous_rv->{processed}) {
        $ou_cni = $ous_rv->{rows}[0]->{shortname};
    }
}

my ($create, $munge) = (0, 0);

my @scns = $record->field('035');

foreach my $id_field ('001', '003') {
    my $spec_value;
    my @controls = $record->field($id_field);

    if ($id_field eq '001') {
        $spec_value = $rec_id;
    } else {
        $spec_value = $ou_cni;
    }

    # Create the 001/003 if none exist
    if (scalar(@controls) == 1) {
        # Only one field; check to see if we need to munge it
        unless (grep $_->data() eq $spec_value, @controls) {
            $munge = 1;
        }
    } else {
        # Delete the other fields, as with more than 1 001/003 we do not know which 003/001 to match
        foreach my $control (@controls) {
            unless ($control->data() eq $spec_value) {
                $record->delete_field($control);
            }
        }
        $record->insert_fields_ordered(MARC::Field->new($id_field, $spec_value));
        $create = 1;
    }
}

# Now, if we need to munge the 001, we will first push the existing 001/003
# into the 035; but if the record did not have one (and one only) 001 and 003
# to begin with, skip this process
if ($munge and not $create) {
    my $scn = "(" . $record->field('003')->data() . ")" . $record->field('001')->data();

    # Do not create duplicate 035 fields
    unless (grep $_->subfield('a') eq $scn, @scns) {
        $record->insert_fields_ordered(MARC::Field->new('035', '', '', 'a' => $scn));
    }
}

# Set the 001/003 and update the MARC
if ($create or $munge) {
    $record->field('001')->data($rec_id);
    $record->field('003')->data($ou_cni);

    my $xml = $record->as_xml_record();
    $xml =~ s/\n//sgo;
    $xml =~ s/^<\?xml.+\?\s*>//go;
    $xml =~ s/>\s+</></go;
    $xml =~ s/\p{Cc}//go;

    # Embed a version of OpenILS::Application::AppUtils->entityize()
    # to avoid having to set PERL5LIB for PostgreSQL as well

    # If we are going to convert non-ASCII characters to XML entities,
    # we had better be dealing with a UTF8 string to begin with
    $xml = decode_utf8($xml);

    $xml = NFC($xml);

    # Convert raw ampersands to entities
    $xml =~ s/&(?!\S+;)/&amp;/gso;

    # Convert Unicode characters to entities
    $xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

    $xml =~ s/[\x00-\x1f]//go;
    $_TD->{new}{marc} = $xml;

    return "MODIFY";
}

return;
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT, BIGINT ) RETURNS TEXT AS $func$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;

    MARC::Charset->assume_unicode(1);

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return undef unless ($r);

    my $id = shift() || $r->subfield( '901' => 'c' );
    $id =~ s/^\s*(?:\([^)]+\))?\s*(.+)\s*?$/$1/;
    return undef unless ($id); # We need an ID!

    my $tmpl = MARC::Record->new();
    $tmpl->encoding( 'UTF-8' );

    my @rule_fields;
    for my $field ( $r->field( '1..' ) ) { # Get main entry fields from the authority record

        my $tag = $field->tag;
        my $i1 = $field->indicator(1);
        my $i2 = $field->indicator(2);
        my $sf = join '', map { $_->[0] } $field->subfields;
        my @data = map { @$_ } $field->subfields;

        my @replace_them;

        # Map the authority field to bib fields it can control.
        if ($tag >= 100 and $tag <= 111) {       # names
            @replace_them = map { $tag + $_ } (0, 300, 500, 600, 700);
        } elsif ($tag eq '130') {                # uniform title
            @replace_them = qw/130 240 440 730 830/;
        } elsif ($tag >= 150 and $tag <= 155) {  # subjects
            @replace_them = ($tag + 500);
        } elsif ($tag >= 180 and $tag <= 185) {  # floating subdivisions
            @replace_them = qw/100 400 600 700 800 110 410 610 710 810 111 411 611 711 811 130 240 440 730 830 650 651 655/;
        } else {
            next;
        }

        # Dummy up the bib-side data
        $tmpl->append_fields(
            map {
                MARC::Field->new( $_, $i1, $i2, @data )
            } @replace_them
        );

        # Construct some 'replace' rules
        push @rule_fields, map { $_ . $sf . '[0~\)' .$id . '$]' } @replace_them;
    }

    # Insert the replace rules into the template
    $tmpl->append_fields(
        MARC::Field->new( '905' => ' ' => ' ' => 'r' => join(',', @rule_fields ) )
    );

    $xml = $tmpl->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT, force_add INT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;
    my $force_add = shift || 0;

    my $target_r = MARC::Record->new_from_xml( $target_xml );
    my $source_r = MARC::Record->new_from_xml( $source_xml );

    return $target_xml unless ($target_r && $source_r);

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
                }
            }
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}{sf}} ) {
            for my $from_field ($source_r->field( $f )) {
                my @tos = $target_r->field( $f );
                if (!@tos) {
                    next if (exists($fields{$f}{match}) and !$force_add);
                    my @new_fields = map { $_->clone } $source_r->field( $f );
                    $target_r->insert_fields_ordered( @new_fields );
                } else {
                    for my $to_field (@tos) {
                        if (exists($fields{$f}{match})) {
                            next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
                        }
                        my @new_sf = map { ($_ => $from_field->subfield($_)) } @{$fields{$f}{sf}};
                        $to_field->add_subfields( @new_sf );
                    }
                }
            }
        } else {
            my @new_fields = map { $_->clone } $source_r->field( $f );
            $target_r->insert_fields_ordered( @new_fields );
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.normalize_heading( TEXT ) RETURNS TEXT AS $func$
    use strict;
    use warnings;

    use utf8;
    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF8');
    use MARC::Charset;
    use UUID::Tiny ':std';

    MARC::Charset->assume_unicode(1);

    my $xml = shift() or return undef;

    my $r;

    # Prevent errors in XML parsing from blowing out ungracefully
    eval {
        $r = MARC::Record->new_from_xml( $xml );
        1;
    } or do {
       return 'BAD_MARCXML_' . create_uuid_as_string(UUID_MD5, $xml);
    };

    if (!$r) {
       return 'BAD_MARCXML_' . create_uuid_as_string(UUID_MD5, $xml);
    }

    # From http://www.loc.gov/standards/sourcelist/subject.html
    my $thes_code_map = {
        a => 'lcsh',
        b => 'lcshac',
        c => 'mesh',
        d => 'nal',
        k => 'cash',
        n => 'notapplicable',
        r => 'aat',
        s => 'sears',
        v => 'rvm',
    };

    # Default to "No attempt to code" if the leader is horribly broken
    my $fixed_field = $r->field('008');
    my $thes_char = '|';
    if ($fixed_field) { 
        $thes_char = substr($fixed_field->data(), 11, 1) || '|';
    }

    my $thes_code = 'UNDEFINED';

    if ($thes_char eq 'z') {
        # Grab the 040 $f per http://www.loc.gov/marc/authority/ad040.html
        $thes_code = $r->subfield('040', 'f') || 'UNDEFINED';
    } elsif ($thes_code_map->{$thes_char}) {
        $thes_code = $thes_code_map->{$thes_char};
    }

    my $auth_txt = '';
    my $head = $r->field('1..');
    if ($head) {
        # Concatenate all of these subfields together, prefixed by their code
        # to prevent collisions along the lines of "Fiction, North Carolina"
        foreach my $sf ($head->subfields()) {
            $auth_txt .= '‡' . $sf->[0] . ' ' . $sf->[1];
        }
    }
    
    if ($auth_txt) {
        my $stmt = spi_prepare('SELECT public.naco_normalize($1) AS norm_text', 'TEXT');
        my $result = spi_exec_prepared($stmt, $auth_txt);
        my $norm_txt = $result->{rows}[0]->{norm_text};
        spi_freeplan($stmt);
        undef($stmt);
        return $head->tag() . "_" . $thes_code . " " . $norm_txt;
    }

    return 'NOHEADING_' . $thes_code . ' ' . create_uuid_as_string(UUID_MD5, $xml);
$func$ LANGUAGE 'plperlu' IMMUTABLE;

CREATE OR REPLACE FUNCTION vandelay.strip_field ( xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
                }
            }
        }
    }

    for my $f ( keys %fields) {
        for my $to_field ($r->field( $f )) {
            if (exists($fields{$f}{match})) {
                next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
            }

            if ( @{$fields{$f}{sf}} ) {
                $to_field->delete_subfield(code => $fields{$f}{sf});
            } else {
                $r->delete_field( $to_field );
            }
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( TEXT ) RETURNS SETOF metabib.full_rec AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;

MARC::Charset->assume_unicode(1);

my $xml = shift;
my $r = MARC::Record->new_from_xml( $xml );

return_next( { tag => 'LDR', value => $r->leader } );

for my $f ( $r->fields ) {
	if ($f->is_control_field) {
		return_next({ tag => $f->tag, value => $f->data });
	} else {
		for my $s ($f->subfields) {
			return_next({
				tag      => $f->tag,
				ind1     => $f->indicator(1),
				ind2     => $f->indicator(2),
				subfield => $s->[0],
				value    => $s->[1]
			});

			if ( $f->tag eq '245' and $s->[0] eq 'a' ) {
				my $trim = $f->indicator(2) || 0;
				return_next({
					tag      => 'tnf',
					ind1     => $f->indicator(1),
					ind2     => $f->indicator(2),
					subfield => 'a',
					value    => substr( $s->[1], $trim )
				});
			}
		}
	}
}

return undef;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( TEXT ) RETURNS SETOF authority.full_rec AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;

MARC::Charset->assume_unicode(1);

my $xml = shift;
my $r = MARC::Record->new_from_xml( $xml );

return_next( { tag => 'LDR', value => $r->leader } );

for my $f ( $r->fields ) {
    if ($f->is_control_field) {
        return_next({ tag => $f->tag, value => $f->data });
    } else {
        for my $s ($f->subfields) {
            return_next({
                tag      => $f->tag,
                ind1     => $f->indicator(1),
                ind2     => $f->indicator(2),
                subfield => $s->[0],
                value    => $s->[1]
            });

        }
    }
}

return undef;

$func$ LANGUAGE PLPERLU;

-- 0529
INSERT INTO config.org_unit_setting_type 
( name, label, description, datatype ) VALUES 
( 'circ.user_merge.delete_addresses', 
  'Circ:  Patron Merge Address Delete', 
  'Delete address(es) of subordinate user(s) in a patron merge', 
   'bool'
);

INSERT INTO config.org_unit_setting_type 
( name, label, description, datatype ) VALUES 
( 'circ.user_merge.delete_cards', 
  'Circ: Patron Merge Barcode Delete', 
  'Delete barcode(s) of subordinate user(s) in a patron merge', 
  'bool'
);

INSERT INTO config.org_unit_setting_type 
( name, label, description, datatype ) VALUES 
( 'circ.user_merge.deactivate_cards', 
  'Circ:  Patron Merge Deactivate Card', 
  'Mark barcode(s) of subordinate user(s) in a patron merge as inactive', 
  'bool'
);

-- 0530
CREATE INDEX actor_usr_day_phone_idx_numeric ON actor.usr USING BTREE 
    (evergreen.lowercase(REGEXP_REPLACE(day_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_evening_phone_idx_numeric ON actor.usr USING BTREE 
    (evergreen.lowercase(REGEXP_REPLACE(evening_phone, '[^0-9]', '', 'g')));

CREATE INDEX actor_usr_other_phone_idx_numeric ON actor.usr USING BTREE 
    (evergreen.lowercase(REGEXP_REPLACE(other_phone, '[^0-9]', '', 'g')));

-- 0533
CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
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

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
        FROM action.all_circulation WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

-- do potentially large updates last to save time if upgrader needs
-- to manually tweak the upgrade script to resolve errors

-- 0505
UPDATE metabib.facet_entry SET value = evergreen.force_unicode_normal_form(value,'NFC');

UPDATE asset.call_number SET id = id;

-- Update reporter.materialized_simple_record with normalized ISBN values
-- This might not get all of them, but most ISBNs will have more than one hyphen
DELETE FROM reporter.materialized_simple_record WHERE id IN (
    SELECT record FROM metabib.full_rec WHERE tag = '020' AND subfield IN ('a', 'z') AND value LIKE '%-%-%'
);

INSERT INTO reporter.materialized_simple_record
    SELECT DISTINCT rossr.* FROM reporter.old_super_simple_record rossr INNER JOIN metabib.full_rec mfr ON mfr.record = rossr.id
        WHERE mfr.tag = '020' AND mfr.subfield IN ('a', 'z') AND mfr.value LIKE '%-%-%'
;

COMMIT;
