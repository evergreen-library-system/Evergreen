--Upgrade Script for 2.1 to 2.2-alpha2

-- Don't require use of -vegversion=something
\set eg_version '''2.2'''

-- DROP objects that might have existed from a prior run of 0526
-- Yes this is ironic.
DROP TABLE IF EXISTS config.db_patch_dependencies;
ALTER TABLE config.upgrade_log DROP COLUMN IF EXISTS applied_to;
DROP FUNCTION IF EXISTS evergreen.upgrade_list_applied_deprecates(TEXT);
DROP FUNCTION IF EXISTS evergreen.upgrade_list_applied_supersedes(TEXT);

BEGIN;
INSERT INTO config.upgrade_log (version) VALUES ('2.2-beta2');

INSERT INTO config.upgrade_log (version) VALUES ('0526'); --miker

CREATE TABLE config.db_patch_dependencies (
  db_patch      TEXT PRIMARY KEY,
  supersedes    TEXT[],
  deprecates    TEXT[]
);

CREATE OR REPLACE FUNCTION evergreen.array_overlap_check (/* field */) RETURNS TRIGGER AS $$
DECLARE
    fld     TEXT;
    cnt     INT;
BEGIN
    fld := TG_ARGV[1];
    EXECUTE 'SELECT COUNT(*) FROM '|| TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME ||' WHERE '|| fld ||' && ($1).'|| fld INTO cnt USING NEW;
    IF cnt > 0 THEN
        RAISE EXCEPTION 'Cannot insert duplicate array into field % of table %', fld, TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER no_overlapping_sups
    BEFORE INSERT OR UPDATE ON config.db_patch_dependencies
    FOR EACH ROW EXECUTE PROCEDURE evergreen.array_overlap_check ('supersedes');

CREATE TRIGGER no_overlapping_deps
    BEFORE INSERT OR UPDATE ON config.db_patch_dependencies
    FOR EACH ROW EXECUTE PROCEDURE evergreen.array_overlap_check ('deprecates');

ALTER TABLE config.upgrade_log
    ADD COLUMN applied_to TEXT;

-- Provide a named type for patching functions
CREATE TYPE evergreen.patch AS (patch TEXT);

-- List applied db patches that are deprecated by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_deprecates ( my_db_patch TEXT ) RETURNS SETOF evergreen.patch AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version::TEXT[] && d.deprecates)
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that are superseded by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_supersedes ( my_db_patch TEXT ) RETURNS SETOF evergreen.patch AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version::TEXT[] && d.supersedes)
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that deprecates (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_deprecated ( my_db_patch TEXT ) RETURNS TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && deprecates
$$ LANGUAGE SQL;

-- List applied db patches that supersedes (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_superseded ( my_db_patch TEXT ) RETURNS TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && supersedes
$$ LANGUAGE SQL;

-- Make sure that no deprecated or superseded db patches are currently applied
CREATE OR REPLACE FUNCTION evergreen.upgrade_verify_no_dep_conflicts ( my_db_patch TEXT ) RETURNS BOOL AS $$
    SELECT  COUNT(*) = 0
      FROM  (SELECT * FROM evergreen.upgrade_list_applied_deprecates( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_supersedes( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_deprecated( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_superseded( $1 ))x
$$ LANGUAGE SQL;

-- Raise an exception if there are, in fact, dep/sup confilct
CREATE OR REPLACE FUNCTION evergreen.upgrade_deps_block_check ( my_db_patch TEXT, my_applied_to TEXT ) RETURNS BOOL AS $$
DECLARE 
    deprecates TEXT;
    supersedes TEXT;
BEGIN
    IF NOT evergreen.upgrade_verify_no_dep_conflicts( my_db_patch ) THEN
        SELECT  STRING_AGG(patch, ', ') INTO deprecates FROM evergreen.upgrade_list_applied_deprecates(my_db_patch);
        SELECT  STRING_AGG(patch, ', ') INTO supersedes FROM evergreen.upgrade_list_applied_supersedes(my_db_patch);
        RAISE EXCEPTION '
Upgrade script % can not be applied:
  applied deprecated scripts %
  applied superseded scripts %
  deprecated by %
  superseded by %',
            my_db_patch,
            ARRAY_AGG(evergreen.upgrade_list_applied_deprecates(my_db_patch)),
            ARRAY_AGG(evergreen.upgrade_list_applied_supersedes(my_db_patch)),
            evergreen.upgrade_list_applied_deprecated(my_db_patch),
            evergreen.upgrade_list_applied_superseded(my_db_patch);
    END IF;

    INSERT INTO config.upgrade_log (version, applied_to) VALUES (my_db_patch, my_applied_to);
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

-- Evergreen DB patch 0536.schema.lazy_circ-barcode_lookup.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
INSERT INTO config.upgrade_log (version) VALUES ('0536');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype) VALUES ( 'circ.staff_client.actor_on_checkout', 'Load patron from Checkout', 'When scanning barcodes into Checkout auto-detect if a new patron barcode is scanned and auto-load the new patron.', 'bool');

CREATE TABLE config.barcode_completion (
    id          SERIAL  PRIMARY KEY,
    active      BOOL    NOT NULL DEFAULT true,
    org_unit    INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    prefix      TEXT,
    suffix      TEXT,
    length      INT     NOT NULL DEFAULT 0,
    padding     TEXT,
    padding_end BOOL    NOT NULL DEFAULT false,
    asset       BOOL    NOT NULL DEFAULT true,
    actor       BOOL    NOT NULL DEFAULT true
);

CREATE TYPE evergreen.barcode_set AS (type TEXT, id BIGINT, barcode TEXT);

CREATE OR REPLACE FUNCTION evergreen.get_barcodes(select_ou INT, type TEXT, in_barcode TEXT) RETURNS SETOF evergreen.barcode_set AS $$
DECLARE
    cur_barcode TEXT;
    barcode_len INT;
    completion_len  INT;
    asset_barcodes  TEXT[];
    actor_barcodes  TEXT[];
    do_asset    BOOL = false;
    do_serial   BOOL = false;
    do_booking  BOOL = false;
    do_actor    BOOL = false;
    completion_set  config.barcode_completion%ROWTYPE;
BEGIN

    IF position('asset' in type) > 0 THEN
        do_asset = true;
    END IF;
    IF position('serial' in type) > 0 THEN
        do_serial = true;
    END IF;
    IF position('booking' in type) > 0 THEN
        do_booking = true;
    END IF;
    IF do_asset OR do_serial OR do_booking THEN
        asset_barcodes = asset_barcodes || in_barcode;
    END IF;
    IF position('actor' in type) > 0 THEN
        do_actor = true;
        actor_barcodes = actor_barcodes || in_barcode;
    END IF;

    barcode_len := length(in_barcode);

    FOR completion_set IN
      SELECT * FROM config.barcode_completion
        WHERE active
        AND org_unit IN (SELECT aou.id FROM actor.org_unit_ancestors(select_ou) aou)
        LOOP
        IF completion_set.prefix IS NULL THEN
            completion_set.prefix := '';
        END IF;
        IF completion_set.suffix IS NULL THEN
            completion_set.suffix := '';
        END IF;
        IF completion_set.length = 0 OR completion_set.padding IS NULL OR length(completion_set.padding) = 0 THEN
            cur_barcode = completion_set.prefix || in_barcode || completion_set.suffix;
        ELSE
            completion_len = completion_set.length - length(completion_set.prefix) - length(completion_set.suffix);
            IF completion_len >= barcode_len THEN
                IF completion_set.padding_end THEN
                    cur_barcode = rpad(in_barcode, completion_len, completion_set.padding);
                ELSE
                    cur_barcode = lpad(in_barcode, completion_len, completion_set.padding);
                END IF;
                cur_barcode = completion_set.prefix || cur_barcode || completion_set.suffix;
            END IF;
        END IF;
        IF completion_set.actor THEN
            actor_barcodes = actor_barcodes || cur_barcode;
        END IF;
        IF completion_set.asset THEN
            asset_barcodes = asset_barcodes || cur_barcode;
        END IF;
    END LOOP;

    IF do_asset AND do_serial THEN
        RETURN QUERY SELECT 'asset'::TEXT, id, barcode FROM ONLY asset.copy WHERE barcode = ANY(asset_barcodes) AND deleted = false;
        RETURN QUERY SELECT 'serial'::TEXT, id, barcode FROM serial.unit WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    ELSIF do_asset THEN
        RETURN QUERY SELECT 'asset'::TEXT, id, barcode FROM asset.copy WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    ELSIF do_serial THEN
        RETURN QUERY SELECT 'serial'::TEXT, id, barcode FROM serial.unit WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    END IF;
    IF do_booking THEN
        RETURN QUERY SELECT 'booking'::TEXT, id::BIGINT, barcode FROM booking.resource WHERE barcode = ANY(asset_barcodes);
    END IF;
    IF do_actor THEN
        RETURN QUERY SELECT 'actor'::TEXT, c.usr::BIGINT, c.barcode FROM actor.card c JOIN actor.usr u ON c.usr = u.id WHERE c.barcode = ANY(actor_barcodes) AND c.active AND NOT u.deleted ORDER BY usr;
    END IF;
    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION evergreen.get_barcodes(INT, TEXT, TEXT) IS $$
Given user input, find an appropriate barcode in the proper class.

Will add prefix/suffix information to do so, and return all results.
$$;



INSERT INTO config.upgrade_log (version) VALUES ('0537'); --miker

DROP FUNCTION evergreen.upgrade_deps_block_check(text,text);
DROP FUNCTION evergreen.upgrade_verify_no_dep_conflicts(text);
DROP FUNCTION evergreen.upgrade_list_applied_deprecated(text);
DROP FUNCTION evergreen.upgrade_list_applied_superseded(text);

-- List applied db patches that deprecates (and block the application of) my_db_patch
CREATE FUNCTION evergreen.upgrade_list_applied_deprecated ( my_db_patch TEXT ) RETURNS SETOF TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && deprecates
$$ LANGUAGE SQL;

-- List applied db patches that supersedes (and block the application of) my_db_patch
CREATE FUNCTION evergreen.upgrade_list_applied_superseded ( my_db_patch TEXT ) RETURNS SETOF TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && supersedes
$$ LANGUAGE SQL;

-- Make sure that no deprecated or superseded db patches are currently applied
CREATE FUNCTION evergreen.upgrade_verify_no_dep_conflicts ( my_db_patch TEXT ) RETURNS BOOL AS $$
    SELECT  COUNT(*) = 0
      FROM  (SELECT * FROM evergreen.upgrade_list_applied_deprecates( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_supersedes( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_deprecated( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_superseded( $1 ))x
$$ LANGUAGE SQL;

-- Raise an exception if there are, in fact, dep/sup confilct
CREATE FUNCTION evergreen.upgrade_deps_block_check ( my_db_patch TEXT, my_applied_to TEXT ) RETURNS BOOL AS $$
BEGIN
    IF NOT evergreen.upgrade_verify_no_dep_conflicts( my_db_patch ) THEN
        RAISE EXCEPTION '
Upgrade script % can not be applied:
  applied deprecated scripts %
  applied superseded scripts %
  deprecated by %
  superseded by %',
            my_db_patch,
            ARRAY_ACCUM(evergreen.upgrade_list_applied_deprecates(my_db_patch)),
            ARRAY_ACCUM(evergreen.upgrade_list_applied_supersedes(my_db_patch)),
            evergreen.upgrade_list_applied_deprecated(my_db_patch),
            evergreen.upgrade_list_applied_superseded(my_db_patch);
    END IF;

    INSERT INTO config.upgrade_log (version, applied_to) VALUES (my_db_patch, my_applied_to);
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;


INSERT INTO config.upgrade_log (version) VALUES ('0544');

INSERT INTO config.usr_setting_type 
( name, opac_visible, label, description, datatype) VALUES 
( 'circ.collections.exempt',
  FALSE, 
  oils_i18n_gettext('circ.collections.exempt', 'Collections: Exempt', 'cust', 'description'),
  oils_i18n_gettext('circ.collections.exempt', 'User is exempt from collections tracking/processing', 'cust', 'description'),
  'bool'
);



SELECT evergreen.upgrade_deps_block_check('0545', :eg_version);

INSERT INTO permission.perm_list VALUES
 (507, 'ABORT_TRANSIT_ON_LOST', oils_i18n_gettext(507, 'Allows a user to abort a transit on a copy with status of LOST', 'ppl', 'description')),
 (508, 'ABORT_TRANSIT_ON_MISSING', oils_i18n_gettext(508, 'Allows a user to abort a transit on a copy with status of MISSING', 'ppl', 'description'));

--- stock Circulation Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        4,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in ('ABORT_TRANSIT_ON_LOST', 'ABORT_TRANSIT_ON_MISSING');

-- Evergreen DB patch 0546.schema.sip_statcats.sql


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0546', :eg_version);

CREATE TABLE actor.stat_cat_sip_fields (
    field   CHAR(2) PRIMARY KEY,
    name    TEXT    NOT NULL,
    one_only  BOOL    NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE actor.stat_cat_sip_fields IS $$
Actor Statistical Category SIP Fields

Contains the list of valid SIP Field identifiers for
Statistical Categories.
$$;
ALTER TABLE actor.stat_cat
    ADD COLUMN sip_field   CHAR(2) REFERENCES actor.stat_cat_sip_fields(field) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN sip_format  TEXT;

CREATE FUNCTION actor.stat_cat_check() RETURNS trigger AS $func$
DECLARE
    sipfield actor.stat_cat_sip_fields%ROWTYPE;
    use_count INT;
BEGIN
    IF NEW.sip_field IS NOT NULL THEN
        SELECT INTO sipfield * FROM actor.stat_cat_sip_fields WHERE field = NEW.sip_field;
        IF sipfield.one_only THEN
            SELECT INTO use_count count(id) FROM actor.stat_cat WHERE sip_field = NEW.sip_field AND id != NEW.id;
            IF use_count > 0 THEN
                RAISE EXCEPTION 'Sip field cannot be used twice';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER actor_stat_cat_sip_update_trigger
    BEFORE INSERT OR UPDATE ON actor.stat_cat FOR EACH ROW
    EXECUTE PROCEDURE actor.stat_cat_check();

CREATE TABLE asset.stat_cat_sip_fields (
    field   CHAR(2) PRIMARY KEY,
    name    TEXT    NOT NULL,
    one_only BOOL    NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE asset.stat_cat_sip_fields IS $$
Asset Statistical Category SIP Fields

Contains the list of valid SIP Field identifiers for
Statistical Categories.
$$;

ALTER TABLE asset.stat_cat
    ADD COLUMN sip_field   CHAR(2) REFERENCES asset.stat_cat_sip_fields(field) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN sip_format  TEXT;

CREATE FUNCTION asset.stat_cat_check() RETURNS trigger AS $func$
DECLARE
    sipfield asset.stat_cat_sip_fields%ROWTYPE;
    use_count INT;
BEGIN
    IF NEW.sip_field IS NOT NULL THEN
        SELECT INTO sipfield * FROM asset.stat_cat_sip_fields WHERE field = NEW.sip_field;
        IF sipfield.one_only THEN
            SELECT INTO use_count count(id) FROM asset.stat_cat WHERE sip_field = NEW.sip_field AND id != NEW.id;
            IF use_count > 0 THEN
                RAISE EXCEPTION 'Sip field cannot be used twice';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER asset_stat_cat_sip_update_trigger
    BEFORE INSERT OR UPDATE ON asset.stat_cat FOR EACH ROW
    EXECUTE PROCEDURE asset.stat_cat_check();



SELECT evergreen.upgrade_deps_block_check('0548', :eg_version); -- dbwells

\qecho This redoes the original part 1 of 0547 which did not apply to rel_2_1,
\qecho and is being added for the sake of clarity

-- delete errant inserts from 0545 (group 4 is NOT the circulation admin group)
DELETE FROM permission.grp_perm_map WHERE grp = 4 AND perm IN (
	SELECT id FROM permission.perm_list
	WHERE code in ('ABORT_TRANSIT_ON_LOST', 'ABORT_TRANSIT_ON_MISSING')
);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulation Administrator' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'ABORT_TRANSIT_ON_LOST',
			'ABORT_TRANSIT_ON_MISSING'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

-- Evergreen DB patch XXXX.data.transit-checkin-interval.sql
--
-- New org unit setting "circ.transit.min_checkin_interval"
-- New TRANSIT_CHECKIN_INTERVAL_BLOCK.override permission
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0549', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'circ.transit.min_checkin_interval',
    oils_i18n_gettext( 
        'circ.transit.min_checkin_interval', 
        'Circ:  Minimum Transit Checkin Interval',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'circ.transit.min_checkin_interval', 
        'In-Transit items checked in this close to the transit start time will be prevented from checking in',
        'coust',
        'label'
    ),
    'interval'
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (  
    509, 
    'TRANSIT_CHECKIN_INTERVAL_BLOCK.override', 
    oils_i18n_gettext(
        509,
        'Allows a user to override the TRANSIT_CHECKIN_INTERVAL_BLOCK event', 
        'ppl', 
        'description'
    )
);

-- add the perm to the default circ admin group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulation Administrator' AND
		aout.name = 'System' AND
		perm.code IN ( 'TRANSIT_CHECKIN_INTERVAL_BLOCK.override' );


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0550', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'org.patron_opt_boundary',
    oils_i18n_gettext( 
        'org.patron_opt_boundary',
        'Circ: Patron Opt-In Boundary',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'org.patron_opt_boundary',
        'This determines at which depth above which patrons must be opted in, and below which patrons will be assumed to be opted in.',
        'coust',
        'label'
    ),
    'integer'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'org.patron_opt_default',
    oils_i18n_gettext( 
        'org.patron_opt_default',
        'Circ: Patron Opt-In Default',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'org.patron_opt_default',
        'This is the default depth at which a patron is opted in; it is calculated as an org unit relative to the current workstation.',
        'coust',
        'label'
    ),
    'integer'
);

-- Evergreen DB patch 0562.schema.copy_active_date.sql
--
-- Active Date


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0562', :eg_version);

ALTER TABLE asset.copy
    ADD COLUMN active_date TIMESTAMP WITH TIME ZONE;

ALTER TABLE auditor.asset_copy_history
    ADD COLUMN active_date TIMESTAMP WITH TIME ZONE;

ALTER TABLE auditor.serial_unit_history
    ADD COLUMN active_date TIMESTAMP WITH TIME ZONE;

ALTER TABLE config.copy_status
    ADD COLUMN copy_active BOOL NOT NULL DEFAULT FALSE;

ALTER TABLE config.circ_matrix_weights
    ADD COLUMN item_age NUMERIC(6,2) NOT NULL DEFAULT 0.0;

ALTER TABLE config.hold_matrix_weights
    ADD COLUMN item_age NUMERIC(6,2) NOT NULL DEFAULT 0.0;

-- The two defaults above were to stop erroring on NOT NULL
-- Remove them here
ALTER TABLE config.circ_matrix_weights
    ALTER COLUMN item_age DROP DEFAULT;

ALTER TABLE config.hold_matrix_weights
    ALTER COLUMN item_age DROP DEFAULT;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN item_age INTERVAL;

ALTER TABLE config.hold_matrix_matchpoint
    ADD COLUMN item_age INTERVAL;

--Removed dupe asset.acp_status_changed

CREATE OR REPLACE FUNCTION asset.acp_created()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
        NEW.active_date := now();
    END IF;
    IF NEW.status_changed_time IS NULL THEN
        NEW.status_changed_time := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_created_trig
    BEFORE INSERT ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_created();

CREATE TRIGGER sunit_created_trig
    BEFORE INSERT ON serial.unit
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_created();

--Removed dupe action.hold_request_permit_test

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
                AND (m.item_age                 IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
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
        weights.usr_grp         := 7.0;
        weights.requestor_grp   := 8.0;
        weights.circ_modifier   := 4.0;
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
            AND (m.item_age             IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
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

DROP INDEX IF EXISTS config.ccmm_once_per_paramset;

DROP INDEX IF EXISTS config.chmm_once_per_paramset;

CREATE UNIQUE INDEX ccmm_once_per_paramset ON config.circ_matrix_matchpoint (org_unit, grp, COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level,''), COALESCE(marc_vr_format, ''), COALESCE(copy_circ_lib::TEXT, ''), COALESCE(copy_owning_lib::TEXT, ''), COALESCE(user_home_ou::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(is_renewal::TEXT, ''), COALESCE(usr_age_lower_bound::TEXT, ''), COALESCE(usr_age_upper_bound::TEXT, ''), COALESCE(item_age::TEXT, '')) WHERE active;

CREATE UNIQUE INDEX chmm_once_per_paramset ON config.hold_matrix_matchpoint (COALESCE(user_home_ou::TEXT, ''), COALESCE(request_ou::TEXT, ''), COALESCE(pickup_ou::TEXT, ''), COALESCE(item_owning_ou::TEXT, ''), COALESCE(item_circ_ou::TEXT, ''), COALESCE(usr_grp::TEXT, ''), COALESCE(requestor_grp::TEXT, ''), COALESCE(circ_modifier, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level, ''), COALESCE(marc_vr_format, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(item_age::TEXT, '')) WHERE active;

UPDATE config.copy_status SET copy_active = true WHERE id IN (0, 1, 7, 8, 10, 12, 15);

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'circ.holds.age_protect.active_date', 'Holds: Use Active Date for Age Protection', 'When calculating age protection rules use the active date instead of the creation date.', 'bool');

-- Assume create date when item is in status we would update active date for anyway
UPDATE asset.copy SET active_date = create_date WHERE status IN (SELECT id FROM config.copy_status WHERE copy_active = true);

-- Assume create date for any item with circs
UPDATE asset.copy SET active_date = create_date WHERE id IN (SELECT id FROM extend_reporter.full_circ_count WHERE circ_count > 0);

-- Assume create date for status change time while we are at it. Because being created WAS a change in status.
UPDATE asset.copy SET status_changed_time = create_date WHERE status_changed_time IS NULL;

-- Evergreen DB patch 0564.data.delete_empty_volume.sql
--
-- New org setting cat.volume.delete_on_empty
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0564', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'cat.volume.delete_on_empty',
        oils_i18n_gettext('cat.volume.delete_on_empty', 'Cat: Delete volume with last copy', 'coust', 'label'),
        oils_i18n_gettext('cat.volume.delete_on_empty', 'Automatically delete a volume when the last linked copy is deleted', 'coust', 'description'),
        'bool'
    );


-- Evergreen DB patch 0565.schema.action-trigger.event_definition.hold-cancel-no-target-notification.sql
--
-- New action trigger event definition: Hold Cancelled (No Target) Email Notification
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0565', :eg_version);

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field, group_field, template)
    VALUES (38, FALSE, 1, 
        'Hold Cancelled (No Target) Email Notification', 
        'hold_request.cancel.expire_no_target', 
        'HoldIsCancelled', 'SendEmail', '30 minutes', 'cancel_time', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Hold Request Cancelled

Dear [% user.family_name %], [% user.first_given_name %]
The following holds were cancelled because no items were found to fullfil the hold.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.rrequest_time), '%Y-%m-%d') %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (38, 'usr'),
    (38, 'pickup_lib'),
    (38, 'bib_rec.bib_record.simple_record');

-- Evergreen DB patch XXXX.data.ou_setting_generate_overdue_on_lost.sql.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0567', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'circ.lost.generate_overdue_on_checkin',
    oils_i18n_gettext( 
        'circ.lost.generate_overdue_on_checkin',
        'Circ:  Lost Checkin Generates New Overdues',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'circ.lost.generate_overdue_on_checkin',
        'Enabling this setting causes retroactive creation of not-yet-existing overdue fines on lost item checkin, up to the point of checkin time (or max fines is reached).  This is different than "restore overdue on lost", because it only creates new overdue fines.  Use both settings together to get the full complement of overdue fines for a lost item',
        'coust',
        'label'
    ),
    'bool'
);

-- Evergreen DB patch 0572.vandelay-record-matching-and-quality.sql
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0572', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT) RETURNS anyarray AS $$ SELECT ARRAY_ACCUM(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2; $$ LANGUAGE SQL;

CREATE TABLE vandelay.match_set (
    id      SERIAL  PRIMARY KEY,
    name    TEXT        NOT NULL,
    owner   INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE,
    mtype   TEXT        NOT NULL DEFAULT 'biblio', -- 'biblio','authority','mfhd'?, others?
    CONSTRAINT name_once_per_owner_mtype UNIQUE (name, owner, mtype)
);

-- Table to define match points, either FF via SVF or tag+subfield
CREATE TABLE vandelay.match_set_point (
    id          SERIAL  PRIMARY KEY,
    match_set   INT     REFERENCES vandelay.match_set (id) ON DELETE CASCADE,
    parent      INT     REFERENCES vandelay.match_set_point (id),
    bool_op     TEXT    CHECK (bool_op IS NULL OR (bool_op IN ('AND','OR','NOT'))),
    svf         TEXT    REFERENCES config.record_attr_definition (name),
    tag         TEXT,
    subfield    TEXT,
    negate      BOOL    DEFAULT FALSE,
    quality     INT     NOT NULL DEFAULT 1, -- higher is better
    CONSTRAINT vmsp_need_a_subfield_with_a_tag CHECK ((tag IS NOT NULL AND subfield IS NOT NULL) OR tag IS NULL),
    CONSTRAINT vmsp_need_a_tag_or_a_ff_or_a_bo CHECK (
        (tag IS NOT NULL AND svf IS NULL AND bool_op IS NULL) OR
        (tag IS NULL AND svf IS NOT NULL AND bool_op IS NULL) OR
        (tag IS NULL AND svf IS NULL AND bool_op IS NOT NULL)
    )
);

CREATE TABLE vandelay.match_set_quality (
    id          SERIAL  PRIMARY KEY,
    match_set   INT     NOT NULL REFERENCES vandelay.match_set (id) ON DELETE CASCADE,
    svf         TEXT    REFERENCES config.record_attr_definition,
    tag         TEXT,
    subfield    TEXT,
    value       TEXT    NOT NULL,
    quality     INT     NOT NULL DEFAULT 1, -- higher is better
    CONSTRAINT vmsq_need_a_subfield_with_a_tag CHECK ((tag IS NOT NULL AND subfield IS NOT NULL) OR tag IS NULL),
    CONSTRAINT vmsq_need_a_tag_or_a_ff CHECK ((tag IS NOT NULL AND svf IS NULL) OR (tag IS NULL AND svf IS NOT NULL))
);
CREATE UNIQUE INDEX vmsq_def_once_per_set ON vandelay.match_set_quality (match_set, COALESCE(tag,''), COALESCE(subfield,''), COALESCE(svf,''), value);


-- ALTER TABLEs...
ALTER TABLE vandelay.queue ADD COLUMN match_set INT REFERENCES vandelay.match_set (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vandelay.queued_record ADD COLUMN quality INT NOT NULL DEFAULT 0;
ALTER TABLE vandelay.bib_attr_definition DROP COLUMN ident;

CREATE TABLE vandelay.import_error (
    code        TEXT    PRIMARY KEY,
    description TEXT    NOT NULL -- i18n
);

ALTER TABLE vandelay.queued_bib_record
    ADD COLUMN import_error TEXT REFERENCES vandelay.import_error (code) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN error_detail TEXT;

ALTER TABLE vandelay.bib_match
    DROP COLUMN field_type,
    DROP COLUMN matched_attr,
    ADD COLUMN quality INT NOT NULL DEFAULT 1,
    ADD COLUMN match_score INT NOT NULL DEFAULT 0;

ALTER TABLE vandelay.import_item
    ADD COLUMN import_error TEXT REFERENCES vandelay.import_error (code) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN error_detail TEXT,
    ADD COLUMN imported_as BIGINT REFERENCES asset.copy (id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN import_time TIMESTAMP WITH TIME ZONE;

ALTER TABLE vandelay.merge_profile ADD COLUMN lwm_ratio NUMERIC;

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

CREATE TYPE vandelay.flat_marc AS ( tag CHAR(3), ind1 TEXT, ind2 TEXT, subfield TEXT, value TEXT );
CREATE OR REPLACE FUNCTION vandelay.flay_marc ( TEXT ) RETURNS SETOF vandelay.flat_marc AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use strict;

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

CREATE OR REPLACE FUNCTION vandelay.flatten_marc ( marc TEXT ) RETURNS SETOF vandelay.flat_marc AS $func$
DECLARE
    output  vandelay.flat_marc%ROWTYPE;
    field   RECORD;
BEGIN
    FOR field IN SELECT * FROM vandelay.flay_marc( marc ) LOOP
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        IF field.subfield IS NOT NULL AND field.tag NOT IN ('020','022','024') THEN -- exclude standard numbers and control fields
            output.value := naco_normalize(field.value, field.subfield);
        ELSE
            output.value := field.value;
        END IF;

        CONTINUE WHEN output.value IS NULL;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT, attr_defs TEXT[]) RETURNS hstore AS $_$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE name IN (SELECT * FROM UNNEST(attr_defs)) ORDER BY format LOOP

        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(x.value), COALESCE(attr_def.joiner,' ')) INTO attr_value
              FROM  vandelay.flatten_marc(xml) AS x
              WHERE x.tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL
                            THEN POSITION(x.subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                        END
              GROUP BY x.tag
              ORDER BY x.tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field(xml, attr_def.fixed_field);

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(xml,xfrm.xslt);
                ELSE
                    transformed_xml := xml;
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
            SELECT  m.value::TEXT INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(xml) v
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

    RETURN new_attrs;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT ) RETURNS hstore AS $_$
    SELECT vandelay.extract_rec_attrs( $1, (SELECT ARRAY_ACCUM(name) FROM config.record_attr_definition));
$_$ LANGUAGE SQL;

-- Everything between this comment and the beginning of the definition of
-- vandelay.match_bib_record() is strictly in service of that function.
CREATE TYPE vandelay.match_set_test_result AS (record BIGINT, quality INTEGER);

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    svf_rstore  HSTORE;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);
    svf_rstore := vandelay.extract_rec_attrs(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(match_set_id);

    query_ := 'SELECT bre.id AS record, ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT ARRAY_TO_STRING(
        ARRAY_ACCUM('COALESCE(n' || q::TEXT || '.quality, 0)'), ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n' ||
        'FROM biblio.record_entry bre ';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT ARRAY_TO_STRING(ARRAY_ACCUM(j), E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n' || 'WHERE ' || wq || ' AND not bre.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore, svf_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;

$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_ACCUM(tag || (COALESCE(subfield, ''))),
            ARRAY_ACCUM(value)
        )
        FROM (
            SELECT tag, subfield, ARRAY_ACCUM(value)::TEXT AS value
                FROM vandelay.flatten_marc(record_xml)
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER
) RETURNS TEXT AS $$
DECLARE
    root    vandelay.match_set_point;
BEGIN
    SELECT * INTO root FROM vandelay.match_set_point
        WHERE parent IS NULL AND match_set = match_set_id;

    RETURN vandelay.get_expr_from_match_set_point(root);
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point
) RETURNS TEXT AS $$
DECLARE
    q           TEXT;
    i           INTEGER;
    this_op     TEXT;
    children    INTEGER[];
    child       vandelay.match_set_point;
BEGIN
    SELECT ARRAY_ACCUM(id) INTO children FROM vandelay.match_set_point
        WHERE parent = node.id;

    IF ARRAY_LENGTH(children, 1) > 0 THEN
        this_op := vandelay._get_expr_render_one(node);
        q := '(';
        i := 1;
        WHILE children[i] IS NOT NULL LOOP
            SELECT * INTO child FROM vandelay.match_set_point
                WHERE id = children[i];
            IF i > 1 THEN
                q := q || ' ' || this_op || ' ';
            END IF;
            i := i + 1;
            q := q || vandelay.get_expr_from_match_set_point(child);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_qrow(
    node vandelay.match_set_point
) RETURNS VOID AS $$
DECLARE
BEGIN
    INSERT INTO _vandelay_tmp_qrows (q) VALUES (node.id);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
BEGIN
    IF node.negate THEN
        op := '<>';
    ELSE
        op := '=';
    END IF;

    IF node.tag IS NOT NULL THEN
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := 'LEFT JOIN (SELECT *, ' || node.quality ||
        ' AS quality FROM metabib.';
    IF node.tag IS NOT NULL THEN
        jrow := jrow || 'full_rec) ' || my_alias || ' ON (' ||
            my_alias || '.record = bre.id AND ' || my_alias || '.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND ' || my_alias || '.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (' || my_alias || '.value ' || op ||
            ' ANY(($1->''' || tagkey || ''')::TEXT[])))';
    ELSE    -- svf
        jrow := jrow || 'record_attr) ' || my_alias || ' ON (' ||
            my_alias || '.id = bre.id AND (' ||
            my_alias || '.attrs->''' || node.svf ||
            ''' ' || op || ' $2->''' || node.svf || '''))';
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_render_one(
    node vandelay.match_set_point
) RETURNS TEXT AS $$
DECLARE
    s           TEXT;
BEGIN
    IF node.bool_op IS NOT NULL THEN
        RETURN node.bool_op;
    ELSE
        RETURN '(n' || node.id::TEXT || '.id IS NOT NULL)';
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.match_bib_record() RETURNS TRIGGER AS $func$
DECLARE
    incoming_existing_id    TEXT;
    test_result             vandelay.match_set_test_result%ROWTYPE;
    tmp_rec                 BIGINT;
    match_set               INT;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT q.match_set INTO match_set FROM vandelay.bib_queue q WHERE q.id = NEW.queue;

    IF match_set IS NOT NULL THEN
        NEW.quality := vandelay.measure_record_quality( NEW.marc, match_set );
    END IF;

    -- Perfect matches on 901$c exit early with a match with high quality.
    incoming_existing_id :=
        oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]', NEW.marc);

    IF incoming_existing_id IS NOT NULL AND incoming_existing_id != '' THEN
        SELECT id INTO tmp_rec FROM biblio.record_entry WHERE id = incoming_existing_id::bigint;
        IF tmp_rec IS NOT NULL THEN
            INSERT INTO vandelay.bib_match (queued_record, eg_record, match_score, quality) 
                SELECT
                    NEW.id, 
                    b.id,
                    9999,
                    -- note: no match_set means quality==0
                    vandelay.measure_record_quality( b.marc, match_set )
                FROM biblio.record_entry b
                WHERE id = incoming_existing_id::bigint;
        END IF;
    END IF;

    IF match_set IS NULL THEN
        RETURN NEW;
    END IF;

    FOR test_result IN SELECT * FROM
        vandelay.match_set_test_marcxml(match_set, NEW.marc) LOOP

        INSERT INTO vandelay.bib_match ( queued_record, eg_record, match_score, quality )
            SELECT  
                NEW.id,
                test_result.record,
                test_result.quality,
                vandelay.measure_record_quality( b.marc, match_set )
	        FROM  biblio.record_entry b
	        WHERE id = test_result.record;

    END LOOP;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.measure_record_quality ( xml TEXT, match_set_id INT ) RETURNS INT AS $_$
DECLARE
    out_q   INT := 0;
    rvalue  TEXT;
    test    vandelay.match_set_quality%ROWTYPE;
BEGIN

    FOR test IN SELECT * FROM vandelay.match_set_quality WHERE match_set = match_set_id LOOP
        IF test.tag IS NOT NULL THEN
            FOR rvalue IN SELECT value FROM vandelay.flatten_marc( xml ) WHERE tag = test.tag AND subfield = test.subfield LOOP
                IF test.value = rvalue THEN
                    out_q := out_q + test.quality;
                END IF;
            END LOOP;
        ELSE
            IF test.value = vandelay.extract_rec_attrs(xml, ARRAY[test.svf]) -> test.svf THEN
                out_q := out_q + test.quality;
            END IF;
        END IF;
    END LOOP;

    RETURN out_q;
END;
$_$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
BEGIN

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    IF vandelay.template_overlay_bib_record( v_marc, eg_id, merge_profile_id) THEN
        UPDATE  vandelay.queued_bib_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;

        editor_string := (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

        IF editor_string IS NOT NULL AND editor_string <> '' THEN
            SELECT usr INTO editor_id FROM actor.card WHERE barcode = editor_string;

            IF editor_id IS NULL THEN
                SELECT id INTO editor_id FROM actor.usr WHERE usrname = editor_string;
            END IF;

            IF editor_id IS NOT NULL THEN
                UPDATE biblio.record_entry SET editor = editor_id WHERE id = eg_id;
            END IF;
        END IF;

        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of biblio.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record_with_best ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    lwm_ratio_value NUMERIC;
BEGIN

    lwm_ratio_value := COALESCE(lwm_ratio_value_p, 0.0);

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.bib_match m
            JOIN vandelay.queued_bib_record qr ON (m.queued_record = qr.id)
            JOIN vandelay.bib_queue q ON (qr.queue = q.id)
            JOIN biblio.record_entry r ON (r.id = m.eg_record)
      WHERE m.queued_record = import_id
            AND qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC >= lwm_ratio_value
      ORDER BY  m.match_score DESC, -- required match score
                qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC DESC, -- quality tie breaker
                m.id -- when in doubt, use the first match
      LIMIT 1;

    IF eg_id IS NULL THEN
        -- RAISE NOTICE 'incoming record is not of high enough quality';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record_with_best ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    lwm_ratio_value NUMERIC;
BEGIN

    lwm_ratio_value := COALESCE(lwm_ratio_value_p, 0.0);

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.bib_match m
            JOIN vandelay.queued_bib_record qr ON (m.queued_record = qr.id)
            JOIN vandelay.bib_queue q ON (qr.queue = q.id)
            JOIN biblio.record_entry r ON (r.id = m.eg_record)
      WHERE m.queued_record = import_id
            AND qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC >= lwm_ratio_value
      ORDER BY  m.match_score DESC, -- required match score
                qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC DESC, -- quality tie breaker
                m.id -- when in doubt, use the first match
      LIMIT 1;

    IF eg_id IS NULL THEN
        -- RAISE NOTICE 'incoming record is not of high enough quality';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue_with_best ( queue_id BIGINT, merge_profile_id INT, lwm_ratio_value NUMERIC ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_bib_record%ROWTYPE;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_bib_record WHERE queue = queue_id AND import_time IS NULL LOOP

        IF vandelay.auto_overlay_bib_record_with_best( queued_record.id, merge_profile_id, lwm_ratio_value ) THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;
    
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue_with_best ( import_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
    SELECT vandelay.auto_overlay_bib_queue_with_best( $1, $2, p.lwm_ratio ) FROM vandelay.merge_profile p WHERE id = $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.ingest_bib_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value   TEXT;
    atype   TEXT;
    adef    RECORD;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    FOR adef IN SELECT * FROM vandelay.bib_attr_definition LOOP

        SELECT extract_marc_field('vandelay.queued_bib_record', id, adef.xpath, adef.remove) INTO value FROM vandelay.queued_bib_record WHERE id = NEW.id;
        IF (value IS NOT NULL AND value <> '') THEN
            INSERT INTO vandelay.queued_bib_record_attr (record, field, attr_value) VALUES (NEW.id, adef.id, value);
        END IF;

    END LOOP;

    RETURN NULL;
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
            opac_visible
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
            item_data.opac_visible
        );
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.cleanup_bib_marc ( ) RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.queued_bib_record_attr WHERE record = OLD.id;
    DELETE FROM vandelay.import_item WHERE record = OLD.id;

    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

-- ALTER TABLEs...

DROP TRIGGER zz_match_bibs_trigger ON vandelay.queued_bib_record;
CREATE TRIGGER zz_match_bibs_trigger
    BEFORE INSERT OR UPDATE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.match_bib_record();

CREATE OR REPLACE FUNCTION vandelay.ingest_authority_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value   TEXT;
    atype   TEXT;
    adef    RECORD;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    FOR adef IN SELECT * FROM vandelay.authority_attr_definition LOOP

        SELECT extract_marc_field('vandelay.queued_authority_record', id, adef.xpath, adef.remove) INTO value FROM vandelay.queued_authority_record WHERE id = NEW.id;
        IF (value IS NOT NULL AND value <> '') THEN
            INSERT INTO vandelay.queued_authority_record_attr (record, field, attr_value) VALUES (NEW.id, adef.id, value);
        END IF;

    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

ALTER TABLE vandelay.authority_attr_definition DROP COLUMN ident;
ALTER TABLE vandelay.queued_authority_record
    ADD COLUMN import_error TEXT REFERENCES vandelay.import_error (code) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN error_detail TEXT;

ALTER TABLE vandelay.authority_match DROP COLUMN matched_attr;

CREATE OR REPLACE FUNCTION vandelay.cleanup_authority_marc ( ) RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.queued_authority_record_attr WHERE record = OLD.id;
    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( rid BIGINT ) RETURNS SETOF authority.full_rec AS $func$
DECLARE
	auth	authority.record_entry%ROWTYPE;
	output	authority.full_rec%ROWTYPE;
	field	RECORD;
BEGIN
	SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

	FOR field IN SELECT * FROM vandelay.flatten_marc( auth.marc ) LOOP
		output.record := rid;
		output.ind1 := field.ind1;
		output.ind2 := field.ind2;
		output.tag := field.tag;
		output.subfield := field.subfield;
		output.value := field.value;

		RETURN NEXT output;
	END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( rid BIGINT ) RETURNS SETOF metabib.full_rec AS $func$
DECLARE
	bib	biblio.record_entry%ROWTYPE;
	output	metabib.full_rec%ROWTYPE;
	field	RECORD;
BEGIN
	SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

	FOR field IN SELECT * FROM vandelay.flatten_marc( bib.marc ) LOOP
		output.record := rid;
		output.ind1 := field.ind1;
		output.ind2 := field.ind2;
		output.tag := field.tag;
		output.subfield := field.subfield;
		output.value := field.value;

		RETURN NEXT output;
	END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-----------------------------------------------
-- Seed data for import errors
-----------------------------------------------

INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'general.unknown', oils_i18n_gettext('general.unknown', 'Import or Overlay failed', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.item.duplicate.barcode', oils_i18n_gettext('import.item.duplicate.barcode', 'Import failed due to barcode collision', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.item.invalid.circ_modifier', oils_i18n_gettext('import.item.invalid.circ_modifier', 'Import failed due to invalid circulation modifier', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.item.invalid.location', oils_i18n_gettext('import.item.invalid.location', 'Import failed due to invalid copy location', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.duplicate.sysid', oils_i18n_gettext('import.duplicate.sysid', 'Import failed due to system id collision', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.duplicate.tcn', oils_i18n_gettext('import.duplicate.sysid', 'Import failed due to system id collision', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'overlay.missing.sysid', oils_i18n_gettext('overlay.missing.sysid', 'Overlay failed due to missing system id', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.auth.duplicate.acn', oils_i18n_gettext('import.auth.duplicate.acn', 'Import failed due to Accession Number collision', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'import.xml.malformed', oils_i18n_gettext('import.xml.malformed', 'Malformed record cause Import failure', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'overlay.xml.malformed', oils_i18n_gettext('overlay.xml.malformed', 'Malformed record cause Overlay failure', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 'overlay.record.quality', oils_i18n_gettext('overlay.record.quality', 'New record had insufficient quality', 'vie', 'description') );


----------------------------------------------------------------
-- Seed data for queued record/item exports
----------------------------------------------------------------

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'vandelay.queued_bib_record.print',
        'vqbr', 
        oils_i18n_gettext(
            'vandelay.queued_bib_record.print',
            'Print output has been requested for records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_bib_record.csv',
        'vqbr', 
        oils_i18n_gettext(
            'vandelay.queued_bib_record.csv',
            'CSV output has been requested for records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_bib_record.email',
        'vqbr', 
        oils_i18n_gettext(
            'vandelay.queued_bib_record.email',
            'An email has been requested for records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_auth_record.print',
        'vqar', 
        oils_i18n_gettext(
            'vandelay.queued_auth_record.print',
            'Print output has been requested for records in an Importer Authority Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_auth_record.csv',
        'vqar', 
        oils_i18n_gettext(
            'vandelay.queued_auth_record.csv',
            'CSV output has been requested for records in an Importer Authority Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.queued_auth_record.email',
        'vqar', 
        oils_i18n_gettext(
            'vandelay.queued_auth_record.email',
            'An email has been requested for records in an Importer Authority Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.import_items.print',
        'vii', 
        oils_i18n_gettext(
            'vandelay.import_items.print',
            'Print output has been requested for Import Items from records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.import_items.csv',
        'vii', 
        oils_i18n_gettext(
            'vandelay.import_items.csv',
            'CSV output has been requested for Import Items from records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'vandelay.import_items.email',
        'vii', 
        oils_i18n_gettext(
            'vandelay.import_items.email',
            'An email has been requested for Import Items from records in an Importer Bib Queue.',
            'ath',
            'description'
        ), 
        FALSE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        39,
        TRUE,
        1,
        'Print Output for Queued Bib Records',
        'vandelay.queued_bib_record.print',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
<pre>
Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqbr IN target %]
=-=-=
 Title of work    | [% helpers.get_queued_bib_attr('title',vqbr.attributes) %]
 Author of work   | [% helpers.get_queued_bib_attr('author',vqbr.attributes) %]
 Language of work | [% helpers.get_queued_bib_attr('language',vqbr.attributes) %]
 Pagination       | [% helpers.get_queued_bib_attr('pagination',vqbr.attributes) %]
 ISBN             | [% helpers.get_queued_bib_attr('isbn',vqbr.attributes) %]
 ISSN             | [% helpers.get_queued_bib_attr('issn',vqbr.attributes) %]
 Price            | [% helpers.get_queued_bib_attr('price',vqbr.attributes) %]
 Accession Number | [% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) %]
 TCN Value        | [% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) %]
 TCN Source       | [% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) %]
 Internal ID      | [% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) %]
 Publisher        | [% helpers.get_queued_bib_attr('publisher',vqbr.attributes) %]
 Publication Date | [% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) %]
 Edition          | [% helpers.get_queued_bib_attr('edition',vqbr.attributes) %]
 Item Barcode     | [% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) %]

    [% END %]
</pre>
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    39, 'attributes')
    ,( 39, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        40,
        TRUE,
        1,
        'CSV Output for Queued Bib Records',
        'vandelay.queued_bib_record.csv',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
"Title of work","Author of work","Language of work","Pagination","ISBN","ISSN","Price","Accession Number","TCN Value","TCN Source","Internal ID","Publisher","Publication Date","Edition","Item Barcode"
[% FOR vqbr IN target %]"[% helpers.get_queued_bib_attr('title',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('author',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('language',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('pagination',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('isbn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('issn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('price',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('publisher',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('edition',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) | replace('"', '""') %]"
[% END %]
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    40, 'attributes')
    ,( 40, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        41,
        TRUE,
        1,
        'Email Output for Queued Bib Records',
        'vandelay.queued_bib_record.email',
        'NOOP_True',
        'SendEmail',
        'queue.owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.queue.owner -%]
To: [%- params.recipient_email || user.email || 'root@localhost' %]
From: [%- params.sender_email || default_sender %]
Subject: Bibs from Import Queue

Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqbr IN target %]
=-=-=
 Title of work    | [% helpers.get_queued_bib_attr('title',vqbr.attributes) %]
 Author of work   | [% helpers.get_queued_bib_attr('author',vqbr.attributes) %]
 Language of work | [% helpers.get_queued_bib_attr('language',vqbr.attributes) %]
 Pagination       | [% helpers.get_queued_bib_attr('pagination',vqbr.attributes) %]
 ISBN             | [% helpers.get_queued_bib_attr('isbn',vqbr.attributes) %]
 ISSN             | [% helpers.get_queued_bib_attr('issn',vqbr.attributes) %]
 Price            | [% helpers.get_queued_bib_attr('price',vqbr.attributes) %]
 Accession Number | [% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) %]
 TCN Value        | [% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) %]
 TCN Source       | [% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) %]
 Internal ID      | [% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) %]
 Publisher        | [% helpers.get_queued_bib_attr('publisher',vqbr.attributes) %]
 Publication Date | [% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) %]
 Edition          | [% helpers.get_queued_bib_attr('edition',vqbr.attributes) %]
 Item Barcode     | [% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) %]

    [% END %]

$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    41, 'attributes')
    ,( 41, 'queue')
    ,( 41, 'queue.owner')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        42,
        TRUE,
        1,
        'Print Output for Queued Authority Records',
        'vandelay.queued_auth_record.print',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
<pre>
Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqar IN target %]
=-=-=
 Record Identifier | [% helpers.get_queued_auth_attr('rec_identifier',vqar.attributes) %]

    [% END %]
</pre>
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    42, 'attributes')
    ,( 42, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        43,
        TRUE,
        1,
        'CSV Output for Queued Authority Records',
        'vandelay.queued_auth_record.csv',
        'NOOP_True',
        'ProcessTemplate',
        'queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
"Record Identifier"
[% FOR vqar IN target %]"[% helpers.get_queued_auth_attr('rec_identifier',vqar.attributes) | replace('"', '""') %]"
[% END %]
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    43, 'attributes')
    ,( 43, 'queue')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        44,
        TRUE,
        1,
        'Email Output for Queued Authority Records',
        'vandelay.queued_auth_record.email',
        'NOOP_True',
        'SendEmail',
        'queue.owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.queue.owner -%]
To: [%- params.recipient_email || user.email || 'root@localhost' %]
From: [%- params.sender_email || default_sender %]
Subject: Authorities from Import Queue

Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqar IN target %]
=-=-=
 Record Identifier | [% helpers.get_queued_auth_attr('rec_identifier',vqar.attributes) %]

    [% END %]

$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    44, 'attributes')
    ,( 44, 'queue')
    ,( 44, 'queue.owner')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        45,
        TRUE,
        1,
        'Print Output for Import Items from Queued Bib Records',
        'vandelay.import_items.print',
        'NOOP_True',
        'ProcessTemplate',
        'record.queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
<pre>
Queue ID: [% target.0.record.queue.id %]
Queue Name: [% target.0.record.queue.name %]
Queue Type: [% target.0.record.queue.queue_type %]
Complete? [% target.0.record.queue.complete %]

    [% FOR vii IN target %]
=-=-=
 Import Item ID         | [% vii.id %]
 Title of work          | [% helpers.get_queued_bib_attr('title',vii.record.attributes) %]
 ISBN                   | [% helpers.get_queued_bib_attr('isbn',vii.record.attributes) %]
 Attribute Definition   | [% vii.definition %]
 Import Error           | [% vii.import_error %]
 Import Error Detail    | [% vii.error_detail %]
 Owning Library         | [% vii.owning_lib %]
 Circulating Library    | [% vii.circ_lib %]
 Call Number            | [% vii.call_number %]
 Copy Number            | [% vii.copy_number %]
 Status                 | [% vii.status.name %]
 Shelving Location      | [% vii.location.name %]
 Circulate              | [% vii.circulate %]
 Deposit                | [% vii.deposit %]
 Deposit Amount         | [% vii.deposit_amount %]
 Reference              | [% vii.ref %]
 Holdable               | [% vii.holdable %]
 Price                  | [% vii.price %]
 Barcode                | [% vii.barcode %]
 Circulation Modifier   | [% vii.circ_modifier %]
 Circulate As MARC Type | [% vii.circ_as_type %]
 Alert Message          | [% vii.alert_message %]
 Public Note            | [% vii.pub_note %]
 Private Note           | [% vii.priv_note %]
 OPAC Visible           | [% vii.opac_visible %]

    [% END %]
</pre>
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    45, 'record')
    ,( 45, 'record.attributes')
    ,( 45, 'record.queue')
    ,( 45, 'record.queue.owner')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        46,
        TRUE,
        1,
        'CSV Output for Import Items from Queued Bib Records',
        'vandelay.import_items.csv',
        'NOOP_True',
        'ProcessTemplate',
        'record.queue.owner',
        'print-on-demand',
$$
[%- USE date -%]
"Import Item ID","Title of work","ISBN","Attribute Definition","Import Error","Import Error Detail","Owning Library","Circulating Library","Call Number","Copy Number","Status","Shelving Location","Circulate","Deposit","Deposit Amount","Reference","Holdable","Price","Barcode","Circulation Modifier","Circulate As MARC Type","Alert Message","Public Note","Private Note","OPAC Visible"
[% FOR vii IN target %]"[% vii.id | replace('"', '""') %]","[% helpers.get_queued_bib_attr('title',vii.record.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('isbn',vii.record.attributes) | replace('"', '""') %]","[% vii.definition | replace('"', '""') %]","[% vii.import_error | replace('"', '""') %]","[% vii.error_detail | replace('"', '""') %]","[% vii.owning_lib | replace('"', '""') %]","[% vii.circ_lib | replace('"', '""') %]","[% vii.call_number | replace('"', '""') %]","[% vii.copy_number | replace('"', '""') %]","[% vii.status.name | replace('"', '""') %]","[% vii.location.name | replace('"', '""') %]","[% vii.circulate | replace('"', '""') %]","[% vii.deposit | replace('"', '""') %]","[% vii.deposit_amount | replace('"', '""') %]","[% vii.ref | replace('"', '""') %]","[% vii.holdable | replace('"', '""') %]","[% vii.price | replace('"', '""') %]","[% vii.barcode | replace('"', '""') %]","[% vii.circ_modifier | replace('"', '""') %]","[% vii.circ_as_type | replace('"', '""') %]","[% vii.alert_message | replace('"', '""') %]","[% vii.pub_note | replace('"', '""') %]","[% vii.priv_note | replace('"', '""') %]","[% vii.opac_visible | replace('"', '""') %]"
[% END %]
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    46, 'record')
    ,( 46, 'record.attributes')
    ,( 46, 'record.queue')
    ,( 46, 'record.queue.owner')
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        47,
        TRUE,
        1,
        'Email Output for Import Items from Queued Bib Records',
        'vandelay.import_items.email',
        'NOOP_True',
        'SendEmail',
        'record.queue.owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.record.queue.owner -%]
To: [%- params.recipient_email || user.email || 'root@localhost' %]
From: [%- params.sender_email || default_sender %]
Subject: Import Items from Import Queue

Queue ID: [% target.0.record.queue.id %]
Queue Name: [% target.0.record.queue.name %]
Queue Type: [% target.0.record.queue.queue_type %]
Complete? [% target.0.record.queue.complete %]

    [% FOR vii IN target %]
=-=-=
 Import Item ID         | [% vii.id %]
 Title of work          | [% helpers.get_queued_bib_attr('title',vii.record.attributes) %]
 ISBN                   | [% helpers.get_queued_bib_attr('isbn',vii.record.attributes) %]
 Attribute Definition   | [% vii.definition %]
 Import Error           | [% vii.import_error %]
 Import Error Detail    | [% vii.error_detail %]
 Owning Library         | [% vii.owning_lib %]
 Circulating Library    | [% vii.circ_lib %]
 Call Number            | [% vii.call_number %]
 Copy Number            | [% vii.copy_number %]
 Status                 | [% vii.status.name %]
 Shelving Location      | [% vii.location.name %]
 Circulate              | [% vii.circulate %]
 Deposit                | [% vii.deposit %]
 Deposit Amount         | [% vii.deposit_amount %]
 Reference              | [% vii.ref %]
 Holdable               | [% vii.holdable %]
 Price                  | [% vii.price %]
 Barcode                | [% vii.barcode %]
 Circulation Modifier   | [% vii.circ_modifier %]
 Circulate As MARC Type | [% vii.circ_as_type %]
 Alert Message          | [% vii.alert_message %]
 Public Note            | [% vii.pub_note %]
 Private Note           | [% vii.priv_note %]
 OPAC Visible           | [% vii.opac_visible %]

    [% END %]
$$
    )
;

INSERT INTO action_trigger.environment ( event_def, path) VALUES (
    47, 'record')
    ,( 47, 'record.attributes')
    ,( 47, 'record.queue')
    ,( 47, 'record.queue.owner')
;



SELECT evergreen.upgrade_deps_block_check('0574', :eg_version);

UPDATE action_trigger.event_definition SET template =
$$
[%- USE date -%]
<style>
    table { border-collapse: collapse; }
    td { padding: 5px; border-bottom: 1px solid #888; }
    th { font-weight: bold; }
</style>
[%
    # Sort the holds into copy-location buckets
    # In the main print loop, sort each bucket by callnumber before printing
    SET holds_list = [];
    SET loc_data = [];
    SET current_location = target.0.current_copy.location.id;
    FOR hold IN target;
        IF current_location != hold.current_copy.location.id;
            SET current_location = hold.current_copy.location.id;
            holds_list.push(loc_data);
            SET loc_data = [];
        END;
        SET hold_data = {
            'hold' => hold,
            'callnumber' => hold.current_copy.call_number.label
        };
        loc_data.push(hold_data);
    END;
    holds_list.push(loc_data)
%]
<table>
    <thead>
        <tr>
            <th>Title</th>
            <th>Author</th>
            <th>Shelving Location</th>
            <th>Call Number</th>
            <th>Barcode/Part</th>
            <th>Patron</th>
        </tr>
    </thead>
    <tbody>
    [% FOR loc_data IN holds_list  %]
        [% FOR hold_data IN loc_data.sort('callnumber') %]
            [%
                SET hold = hold_data.hold;
                SET copy_data = helpers.get_copy_bib_basics(hold.current_copy.id);
            %]
            <tr>
                <td>[% copy_data.title | truncate %]</td>
                <td>[% copy_data.author | truncate %]</td>
                <td>[% hold.current_copy.location.name %]</td>
                <td>[% hold.current_copy.call_number.label %]</td>
                <td>[% hold.current_copy.barcode %]
                    [% FOR part IN hold.current_copy.parts %]
                       [% part.part.label %]
                    [% END %]
                </td>
                <td>[% hold.usr.card.barcode %]</td>
            </tr>
        [% END %]
    [% END %]
    <tbody>
</table>
$$
    WHERE id = 35;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES
        (35, 'current_copy.parts'),
        (35, 'current_copy.parts.part')
;


-- Evergreen DB patch XXXX.schema.authority-control-sets.sql
--
-- Schema upgrade to add Authority Control Set functionality
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0575', :eg_version);

CREATE TABLE authority.control_set (
    id          SERIAL  PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT                     -- i18n
);

CREATE TABLE authority.control_set_authority_field (
    id          SERIAL  PRIMARY KEY,
    main_entry  INT     REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    control_set INT     NOT NULL REFERENCES authority.control_set (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    tag         CHAR(3) NOT NULL,
    nfi CHAR(1),
    sf_list     TEXT    NOT NULL,
    name        TEXT    NOT NULL, -- i18n
    description TEXT              -- i18n
);

CREATE TABLE authority.control_set_bib_field (
    id              SERIAL  PRIMARY KEY,
    authority_field INT     NOT NULL REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    tag             CHAR(3) NOT NULL
);

CREATE TABLE authority.thesaurus (
    code        TEXT    PRIMARY KEY,     -- MARC21 thesaurus code
    control_set INT     NOT NULL REFERENCES authority.control_set (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT                     -- i18n
);

CREATE TABLE authority.browse_axis (
    code        TEXT    PRIMARY KEY,
    name        TEXT    UNIQUE NOT NULL, -- i18n
    sorter      TEXT    REFERENCES config.record_attr_definition (name) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    description TEXT
);

CREATE TABLE authority.browse_axis_authority_field_map (
    id          SERIAL  PRIMARY KEY,
    axis        TEXT    NOT NULL REFERENCES authority.browse_axis (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    field       INT     NOT NULL REFERENCES authority.control_set_authority_field (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

ALTER TABLE authority.record_entry ADD COLUMN control_set INT REFERENCES authority.control_set (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE authority.rec_descriptor DROP COLUMN char_encoding, ADD COLUMN encoding_level TEXT, ADD COLUMN thesaurus TEXT;

CREATE INDEX authority_full_rec_value_index ON authority.full_rec (value);
CREATE OR REPLACE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id; DELETE FROM authority.full_rec WHERE record = OLD.id);
 
CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT, no_thesaurus BOOL ) RETURNS TEXT AS $func$
DECLARE
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    sf              TEXT;
    thes_code       TEXT;
    cset            INT;
    heading_text    TEXT;
    tmp_text        TEXT;
BEGIN
    thes_code := vandelay.marc21_extract_fixed_field(marcxml,'Subj');
    IF thes_code IS NULL THEN
        thes_code := '|';
    END IF;

    SELECT control_set INTO cset FROM authority.thesaurus WHERE code = thes_code;
    IF NOT FOUND THEN
        cset = 1;
    END IF;

    heading_text := '';
    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset AND main_entry IS NULL LOOP
        tag_used := acsaf.tag;
        FOR sf IN SELECT * FROM regexp_split_to_table(acsaf.sf_list,'') LOOP
            tmp_text := oils_xpath_string('//*[@tag="'||tag_used||'"]/*[@code="'||sf||'"]', marcxml);
            IF tmp_text IS NOT NULL AND tmp_text <> '' THEN
                heading_text := heading_text || E'\u2021' || sf || ' ' || tmp_text;
            END IF;
        END LOOP;
        EXIT WHEN heading_text <> '';
    END LOOP;
 
    IF thes_code = 'z' THEN
        thes_code := oils_xpath_string('//*[@tag="040"]/*[@code="f"][1]', marcxml);
    END IF;

    IF heading_text <> '' THEN
        IF no_thesaurus IS TRUE THEN
            heading_text := tag_used || ' ' || public.naco_normalize(heading_text);
        ELSE
            heading_text := tag_used || '_' || thes_code || ' ' || public.naco_normalize(heading_text);
        END IF;
    ELSE
        heading_text := 'NOHEADING_' || thes_code || ' ' || MD5(marcxml);
    END IF;

    RETURN heading_text;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.simple_normalize_heading( marcxml TEXT ) RETURNS TEXT AS $func$
    SELECT authority.normalize_heading($1, TRUE);
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT ) RETURNS TEXT AS $func$
    SELECT authority.normalize_heading($1, FALSE);
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE VIEW authority.tracing_links AS
    SELECT  main.record AS record,
            main.id AS main_id,
            main.tag AS main_tag,
            oils_xpath_string('//*[@tag="'||main.tag||'"]/*[local-name()="subfield"]', are.marc) AS main_value,
            substr(link.value,1,1) AS relationship,
            substr(link.value,2,1) AS use_restriction,
            substr(link.value,3,1) AS deprecation,
            substr(link.value,4,1) AS display_restriction,
            link.id AS link_id,
            link.tag AS link_tag,
            oils_xpath_string('//*[@tag="'||link.tag||'"]/*[local-name()="subfield"]', are.marc) AS link_value,
            authority.normalize_heading(are.marc) AS normalized_main_value
      FROM  authority.full_rec main
            JOIN authority.record_entry are ON (main.record = are.id)
            JOIN authority.control_set_authority_field main_entry
                ON (main_entry.tag = main.tag
                    AND main_entry.main_entry IS NULL
                    AND main.subfield = 'a' )
            JOIN authority.control_set_authority_field sub_entry
                ON (main_entry.id = sub_entry.main_entry)
            JOIN authority.full_rec link
                ON (link.record = main.record
                    AND link.tag = sub_entry.tag
                    AND link.subfield = 'w' );
 
CREATE OR REPLACE FUNCTION authority.generate_overlay_template (source_xml TEXT) RETURNS TEXT AS $f$
DECLARE
    cset                INT;
    main_entry          authority.control_set_authority_field%ROWTYPE;
    bib_field           authority.control_set_bib_field%ROWTYPE;
    auth_id             INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', source_xml)::INT;
    replace_data        XML[] DEFAULT '{}'::XML[];
    replace_rules       TEXT[] DEFAULT '{}'::TEXT[];
    auth_field          XML[];
BEGIN
    IF auth_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Default to the LoC controll set
    SELECT COALESCE(control_set,1) INTO cset FROM authority.record_entry WHERE id = auth_id;

    FOR main_entry IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP
        auth_field := XPATH('//*[@tag="'||main_entry.tag||'"][1]',source_xml::XML);
        IF ARRAY_LENGTH(auth_field,1) > 0 THEN
            FOR bib_field IN SELECT * FROM authority.control_set_bib_field WHERE authority_field = main_entry.id LOOP
                replace_data := replace_data || XMLELEMENT( name datafield, XMLATTRIBUTES(bib_field.tag AS tag), XPATH('//*[local-name()="subfield"]',auth_field[1])::XML[]);
                replace_rules := replace_rules || ( bib_field.tag || main_entry.sf_list || E'[0~\\)' || auth_id || '$]' );
            END LOOP;
            EXIT;
        END IF;
    END LOOP;
 
    RETURN XMLELEMENT(
        name record,
        XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
        XMLELEMENT( name leader, '00881nam a2200193   4500'),
        replace_data,
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
 
CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( BIGINT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( marc ) FROM authority.record_entry WHERE id = $1;
$func$ LANGUAGE SQL;
 
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
                        my @new_sf = map { ($_ => $from_field->subfield($_)) } grep { defined($from_field->subfield($_)) } @{$fields{$f}{sf}};
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


CREATE INDEX by_heading ON authority.record_entry (authority.simple_normalize_heading(marc)) WHERE deleted IS FALSE or deleted = FALSE;

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, search_field, facet_field) VALUES
    (28, 'identifier', 'authority_id', oils_i18n_gettext(28, 'Authority Record ID', 'cmf', 'label'), 'marcxml', '//marc:datafield/marc:subfield[@code="0"]', FALSE, TRUE);
 
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('AUT','z',' ');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('MFHD','uvxy',' ');
 
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'AUT', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Subj', '008', 'AUT', 11, 1, '|');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('RecStat', 'ldr', 'AUT', 5, 1, 'n');
 
INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func = 'remove_paren_substring'
            AND m.id IN (28);

SELECT SETVAL('authority.control_set_id_seq'::TEXT, 100);
SELECT SETVAL('authority.control_set_authority_field_id_seq'::TEXT, 1000);
SELECT SETVAL('authority.control_set_bib_field_id_seq'::TEXT, 1000);

INSERT INTO authority.control_set (id, name, description) VALUES (
    1,
    oils_i18n_gettext('1','LoC','acs','name'),
    oils_i18n_gettext('1','Library of Congress standard authority record control semantics','acs','description')
);

INSERT INTO authority.control_set_authority_field (id, control_set, main_entry, tag, sf_list, name) VALUES

-- Main entries
    (1, 1, NULL, '100', 'abcdefklmnopqrstvxyz', oils_i18n_gettext('1','Heading -- Personal Name','acsaf','name')),
    (2, 1, NULL, '110', 'abcdefgklmnoprstvxyz', oils_i18n_gettext('2','Heading -- Corporate Name','acsaf','name')),
    (3, 1, NULL, '111', 'acdefgklnpqstvxyz', oils_i18n_gettext('3','Heading -- Meeting Name','acsaf','name')),
    (4, 1, NULL, '130', 'adfgklmnoprstvxyz', oils_i18n_gettext('4','Heading -- Uniform Title','acsaf','name')),
    (5, 1, NULL, '150', 'abvxyz', oils_i18n_gettext('5','Heading -- Topical Term','acsaf','name')),
    (6, 1, NULL, '151', 'avxyz', oils_i18n_gettext('6','Heading -- Geographic Name','acsaf','name')),
    (7, 1, NULL, '155', 'avxyz', oils_i18n_gettext('7','Heading -- Genre/Form Term','acsaf','name')),
    (8, 1, NULL, '180', 'vxyz', oils_i18n_gettext('8','Heading -- General Subdivision','acsaf','name')),
    (9, 1, NULL, '181', 'vxyz', oils_i18n_gettext('9','Heading -- Geographic Subdivision','acsaf','name')),
    (10, 1, NULL, '182', 'vxyz', oils_i18n_gettext('10','Heading -- Chronological Subdivision','acsaf','name')),
    (11, 1, NULL, '185', 'vxyz', oils_i18n_gettext('11','Heading -- Form Subdivision','acsaf','name')),
    (12, 1, NULL, '148', 'avxyz', oils_i18n_gettext('12','Heading -- Chronological Term','acsaf','name')),

-- See Also From tracings
    (21, 1, 1, '500', 'abcdefiklmnopqrstvwxyz4', oils_i18n_gettext('21','See Also From Tracing -- Personal Name','acsaf','name')),
    (22, 1, 2, '510', 'abcdefgiklmnoprstvwxyz4', oils_i18n_gettext('22','See Also From Tracing -- Corporate Name','acsaf','name')),
    (23, 1, 3, '511', 'acdefgiklnpqstvwxyz4', oils_i18n_gettext('23','See Also From Tracing -- Meeting Name','acsaf','name')),
    (24, 1, 4, '530', 'adfgiklmnoprstvwxyz4', oils_i18n_gettext('24','See Also From Tracing -- Uniform Title','acsaf','name')),
    (25, 1, 5, '550', 'abivwxyz4', oils_i18n_gettext('25','See Also From Tracing -- Topical Term','acsaf','name')),
    (26, 1, 6, '551', 'aivwxyz4', oils_i18n_gettext('26','See Also From Tracing -- Geographic Name','acsaf','name')),
    (27, 1, 7, '555', 'aivwxyz4', oils_i18n_gettext('27','See Also From Tracing -- Genre/Form Term','acsaf','name')),
    (28, 1, 8, '580', 'ivwxyz4', oils_i18n_gettext('28','See Also From Tracing -- General Subdivision','acsaf','name')),
    (29, 1, 9, '581', 'ivwxyz4', oils_i18n_gettext('29','See Also From Tracing -- Geographic Subdivision','acsaf','name')),
    (30, 1, 10, '582', 'ivwxyz4', oils_i18n_gettext('30','See Also From Tracing -- Chronological Subdivision','acsaf','name')),
    (31, 1, 11, '585', 'ivwxyz4', oils_i18n_gettext('31','See Also From Tracing -- Form Subdivision','acsaf','name')),
    (32, 1, 12, '548', 'aivwxyz4', oils_i18n_gettext('32','See Also From Tracing -- Chronological Term','acsaf','name')),

-- Linking entries
    (41, 1, 1, '700', 'abcdefghjklmnopqrstvwxyz25', oils_i18n_gettext('41','Established Heading Linking Entry -- Personal Name','acsaf','name')),
    (42, 1, 2, '710', 'abcdefghklmnoprstvwxyz25', oils_i18n_gettext('42','Established Heading Linking Entry -- Corporate Name','acsaf','name')),
    (43, 1, 3, '711', 'acdefghklnpqstvwxyz25', oils_i18n_gettext('43','Established Heading Linking Entry -- Meeting Name','acsaf','name')),
    (44, 1, 4, '730', 'adfghklmnoprstvwxyz25', oils_i18n_gettext('44','Established Heading Linking Entry -- Uniform Title','acsaf','name')),
    (45, 1, 5, '750', 'abvwxyz25', oils_i18n_gettext('45','Established Heading Linking Entry -- Topical Term','acsaf','name')),
    (46, 1, 6, '751', 'avwxyz25', oils_i18n_gettext('46','Established Heading Linking Entry -- Geographic Name','acsaf','name')),
    (47, 1, 7, '755', 'avwxyz25', oils_i18n_gettext('47','Established Heading Linking Entry -- Genre/Form Term','acsaf','name')),
    (48, 1, 8, '780', 'vwxyz25', oils_i18n_gettext('48','Subdivision Linking Entry -- General Subdivision','acsaf','name')),
    (49, 1, 9, '781', 'vwxyz25', oils_i18n_gettext('49','Subdivision Linking Entry -- Geographic Subdivision','acsaf','name')),
    (50, 1, 10, '782', 'vwxyz25', oils_i18n_gettext('50','Subdivision Linking Entry -- Chronological Subdivision','acsaf','name')),
    (51, 1, 11, '785', 'vwxyz25', oils_i18n_gettext('51','Subdivision Linking Entry -- Form Subdivision','acsaf','name')),
    (52, 1, 12, '748', 'avwxyz25', oils_i18n_gettext('52','Established Heading Linking Entry -- Chronological Term','acsaf','name')),

-- See From tracings
    (61, 1, 1, '400', 'abcdefiklmnopqrstvwxyz4', oils_i18n_gettext('61','See Also Tracing -- Personal Name','acsaf','name')),
    (62, 1, 2, '410', 'abcdefgiklmnoprstvwxyz4', oils_i18n_gettext('62','See Also Tracing -- Corporate Name','acsaf','name')),
    (63, 1, 3, '411', 'acdefgiklnpqstvwxyz4', oils_i18n_gettext('63','See Also Tracing -- Meeting Name','acsaf','name')),
    (64, 1, 4, '430', 'adfgiklmnoprstvwxyz4', oils_i18n_gettext('64','See Also Tracing -- Uniform Title','acsaf','name')),
    (65, 1, 5, '450', 'abivwxyz4', oils_i18n_gettext('65','See Also Tracing -- Topical Term','acsaf','name')),
    (66, 1, 6, '451', 'aivwxyz4', oils_i18n_gettext('66','See Also Tracing -- Geographic Name','acsaf','name')),
    (67, 1, 7, '455', 'aivwxyz4', oils_i18n_gettext('67','See Also Tracing -- Genre/Form Term','acsaf','name')),
    (68, 1, 8, '480', 'ivwxyz4', oils_i18n_gettext('68','See Also Tracing -- General Subdivision','acsaf','name')),
    (69, 1, 9, '481', 'ivwxyz4', oils_i18n_gettext('69','See Also Tracing -- Geographic Subdivision','acsaf','name')),
    (70, 1, 10, '482', 'ivwxyz4', oils_i18n_gettext('70','See Also Tracing -- Chronological Subdivision','acsaf','name')),
    (71, 1, 11, '485', 'ivwxyz4', oils_i18n_gettext('71','See Also Tracing -- Form Subdivision','acsaf','name')),
    (72, 1, 12, '448', 'aivwxyz4', oils_i18n_gettext('72','See Also Tracing -- Chronological Term','acsaf','name'));

INSERT INTO authority.browse_axis (code,name,description,sorter) VALUES
    ('title','Title','Title axis','titlesort'),
    ('author','Author','Author axis','titlesort'),
    ('subject','Subject','Subject axis','titlesort'),
    ('topic','Topic','Topic Subject axis','titlesort');

INSERT INTO authority.browse_axis_authority_field_map (axis,field) VALUES
    ('author',  1 ),
    ('author',  2 ),
    ('author',  3 ),
    ('title',   4 ),
    ('topic',   5 ),
    ('subject', 5 ),
    ('subject', 6 ),
    ('subject', 7 ),
    ('subject', 12);

INSERT INTO authority.control_set_bib_field (tag, authority_field) 
    SELECT '100', id FROM authority.control_set_authority_field WHERE tag IN ('100')
        UNION
    SELECT '600', id FROM authority.control_set_authority_field WHERE tag IN ('100','180','181','182','185')
        UNION
    SELECT '700', id FROM authority.control_set_authority_field WHERE tag IN ('100')
        UNION
    SELECT '800', id FROM authority.control_set_authority_field WHERE tag IN ('100')
        UNION

    SELECT '110', id FROM authority.control_set_authority_field WHERE tag IN ('110')
        UNION
    SELECT '610', id FROM authority.control_set_authority_field WHERE tag IN ('110')
        UNION
    SELECT '710', id FROM authority.control_set_authority_field WHERE tag IN ('110')
        UNION
    SELECT '810', id FROM authority.control_set_authority_field WHERE tag IN ('110')
        UNION

    SELECT '111', id FROM authority.control_set_authority_field WHERE tag IN ('111')
        UNION
    SELECT '611', id FROM authority.control_set_authority_field WHERE tag IN ('111')
        UNION
    SELECT '711', id FROM authority.control_set_authority_field WHERE tag IN ('111')
        UNION
    SELECT '811', id FROM authority.control_set_authority_field WHERE tag IN ('111')
        UNION

    SELECT '130', id FROM authority.control_set_authority_field WHERE tag IN ('130')
        UNION
    SELECT '240', id FROM authority.control_set_authority_field WHERE tag IN ('130')
        UNION
    SELECT '630', id FROM authority.control_set_authority_field WHERE tag IN ('130')
        UNION
    SELECT '730', id FROM authority.control_set_authority_field WHERE tag IN ('130')
        UNION
    SELECT '830', id FROM authority.control_set_authority_field WHERE tag IN ('130')
        UNION

    SELECT '648', id FROM authority.control_set_authority_field WHERE tag IN ('148')
        UNION

    SELECT '650', id FROM authority.control_set_authority_field WHERE tag IN ('150','180','181','182','185')
        UNION
    SELECT '651', id FROM authority.control_set_authority_field WHERE tag IN ('151','180','181','182','185')
        UNION
    SELECT '655', id FROM authority.control_set_authority_field WHERE tag IN ('155','180','181','182','185')
;

INSERT INTO authority.thesaurus (code, name, control_set) VALUES
    ('a', oils_i18n_gettext('a','Library of Congress Subject Headings','at','name'), 1),
    ('b', oils_i18n_gettext('b',$$LC subject headings for children's literature$$,'at','name'), 1), -- silly vim '
    ('c', oils_i18n_gettext('c','Medical Subject Headings','at','name'), 1),
    ('d', oils_i18n_gettext('d','National Agricultural Library subject authority file','at','name'), 1),
    ('k', oils_i18n_gettext('k','Canadian Subject Headings','at','name'), 1),
    ('n', oils_i18n_gettext('n','Not applicable','at','name'), 1),
    ('r', oils_i18n_gettext('r','Art and Architecture Thesaurus','at','name'), 1),
    ('s', oils_i18n_gettext('s','Sears List of Subject Headings','at','name'), 1),
    ('v', oils_i18n_gettext('v','Repertoire de vedettes-matiere','at','name'), 1),
    ('z', oils_i18n_gettext('z','Other','at','name'), 1),
    ('|', oils_i18n_gettext('|','No attempt to code','at','name'), 1);
 
CREATE OR REPLACE FUNCTION authority.map_thesaurus_to_control_set () RETURNS TRIGGER AS $func$
BEGIN
    IF NEW.control_set IS NULL THEN
        SELECT  control_set INTO NEW.control_set
          FROM  authority.thesaurus
          WHERE vandelay.marc21_extract_fixed_field(NEW.marc,'Subj') = code;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER map_thesaurus_to_control_set BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.map_thesaurus_to_control_set ();

CREATE OR REPLACE FUNCTION authority.reingest_authority_rec_descriptor( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.rec_descriptor WHERE record = auth_id;
    INSERT INTO authority.rec_descriptor (record, record_status, encoding_level, thesaurus)
        SELECT  auth_id,
                vandelay.marc21_extract_fixed_field(marc,'RecStat'),
                vandelay.marc21_extract_fixed_field(marc,'ELvl'),
                vandelay.marc21_extract_fixed_field(marc,'Subj')
          FROM  authority.record_entry
          WHERE id = auth_id;
     RETURN;
 END;
 $func$ LANGUAGE PLPGSQL;

--Removed dupe authority.indexing_ingest_or_delete

-- Evergreen DB patch 0577.schema.vandelay-item-import-copy-loc-ancestors.sql
--
-- Ingest items copy location inheritance
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0577', :eg_version); -- berick

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

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id;

        -- Build the combined XPath

        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;

        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;

        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;

        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;

        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;

        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;

        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;

        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;

        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;

        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;

        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;

        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;

        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;

        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;

        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;

        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;

        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;


        xpath :=
            owning_lib      || '|' ||
            circ_lib        || '|' ||
            call_number     || '|' ||
            copy_number     || '|' ||
            status          || '|' ||
            location        || '|' ||
            circulate       || '|' ||
            deposit         || '|' ||
            deposit_amount  || '|' ||
            ref             || '|' ||
            holdable        || '|' ||
            price           || '|' ||
            barcode         || '|' ||
            circ_modifier   || '|' ||
            circ_as_type    || '|' ||
            alert_message   || '|' ||
            pub_note        || '|' ||
            priv_note       || '|' ||
            opac_visible;

        -- RAISE NOTICE 'XPath: %', xpath;

        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id INT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, opac_vis TEXT )
        LOOP

            tmp_attr_set.pr = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
            tmp_attr_set.dep_amount = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');

            tmp_attr_set.pr := NULLIF( tmp_attr_set.pr, '' );
            tmp_attr_set.dep_amount := NULLIF( tmp_attr_set.dep_amount, '' );

            SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
            SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
            SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT


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
                ORDER BY a.depth DESC
                LIMIT 1; 

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

            attr_set.copy_number    := tmp_attr_set.cnum::INT; -- INT,
            attr_set.deposit_amount := tmp_attr_set.dep_amount::NUMERIC(6,2); -- NUMERIC(6,2),
            attr_set.price          := tmp_attr_set.pr::NUMERIC(8,2); -- NUMERIC(8,2),

            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.circ_modifier  := tmp_attr_set.circ_mod; -- TEXT,
            attr_set.circ_as_type   := tmp_attr_set.circ_as; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,

            RETURN NEXT attr_set;

        END LOOP;

    END IF;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;


-- Evergreen DB patch XXXX.data.org-setting-ui.circ.billing.uncheck_bills_and_unfocus_payment_box.sql
--
-- New org setting ui.circ.billing.uncheck_bills_and_unfocus_payment_box
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0584', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
        oils_i18n_gettext(
            'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
            'GUI: Uncheck bills by default in the patron billing interface',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.circ.billing.uncheck_bills_and_unfocus_payment_box',
            'Uncheck bills by default in the patron billing interface,'
            || ' and focus on the Uncheck All button instead of the'
            || ' Payment Received field.',
            'coust',
            'description'
        ),
        'bool'
    );


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0585', :eg_version);

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'circ.checkout_fills_related_hold_exact_match_only',
    'Checkout Fills Related Hold On Valid Copy Only',
    'When filling related holds on checkout only match on items that are valid for opportunistic capture for the hold. Without this set a Title or Volume hold could match when the item is not holdable. With this set only holdable items will match.',
    'bool');


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0586', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES (
    511,
    'PERSISTENT_LOGIN',
    oils_i18n_gettext(
        511,
        'Allows a user to authenticate and get a long-lived session (length configured in opensrf.xml)',
        'ppl',
        'description'
    )
);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, FALSE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Users' AND
        aout.name = 'Consortium' AND
        perm.code = 'PERSISTENT_LOGIN';

\qecho 
\qecho If this transaction succeeded, your users (staff and patrons) now have
\qecho the PERSISTENT_LOGIN permission by default.
\qecho 


-- Evergreen DB patch XXXX.data.org-setting-circ.offline.skip_foo_if_newer_status_changed_time.sql
--
-- New org setting circ.offline.skip_checkout_if_newer_status_changed_time
-- New org setting circ.offline.skip_renew_if_newer_status_changed_time
-- New org setting circ.offline.skip_checkin_if_newer_status_changed_time
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0593', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'circ.offline.skip_checkout_if_newer_status_changed_time',
        oils_i18n_gettext(
            'circ.offline.skip_checkout_if_newer_status_changed_time',
            'Offline: Skip offline checkout if newer item Status Changed Time.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.offline.skip_checkout_if_newer_status_changed_time',
            'Skip offline checkout transaction (raise exception when'
            || ' processing) if item Status Changed Time is newer than the'
            || ' recorded transaction time.  WARNING: The Reshelving to'
            || ' Available status rollover will trigger this.',
            'coust',
            'description'
        ),
        'bool'
    ),( 
        'circ.offline.skip_renew_if_newer_status_changed_time',
        oils_i18n_gettext(
            'circ.offline.skip_renew_if_newer_status_changed_time',
            'Offline: Skip offline renewal if newer item Status Changed Time.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.offline.skip_renew_if_newer_status_changed_time',
            'Skip offline renewal transaction (raise exception when'
            || ' processing) if item Status Changed Time is newer than the'
            || ' recorded transaction time.  WARNING: The Reshelving to'
            || ' Available status rollover will trigger this.',
            'coust',
            'description'
        ),
        'bool'
    ),( 
        'circ.offline.skip_checkin_if_newer_status_changed_time',
        oils_i18n_gettext(
            'circ.offline.skip_checkin_if_newer_status_changed_time',
            'Offline: Skip offline checkin if newer item Status Changed Time.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.offline.skip_checkin_if_newer_status_changed_time',
            'Skip offline checkin transaction (raise exception when'
            || ' processing) if item Status Changed Time is newer than the'
            || ' recorded transaction time.  WARNING: The Reshelving to'
            || ' Available status rollover will trigger this.',
            'coust',
            'description'
        ),
        'bool'
    );

-- Evergreen DB patch YYYY.schema.acp_status_date_changed.sql
--
-- Change trigger which updates copy status_changed_time to ignore the
-- Reshelving->Available status rollover

-- FIXME: 0039.schema.acp_status_date_changed.sql defines this the first time
-- around, but along with the column itself, etc.  And it gets modified with
-- 0562.schema.copy_active_date.sql.  Not sure how to use the supercedes /
-- deprecate stuff for upgrade scripts, if it's even applicable when a given
-- upgrade script is doing so much.

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0594', :eg_version);

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.status <> OLD.status AND NOT (NEW.status = 0 AND OLD.status = 7) THEN
        NEW.status_changed_time := now();
        IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
            NEW.active_date := now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Evergreen DB patch 0595.data.org-setting-ui.patron_search.result_cap.sql
--
-- New org setting ui.patron_search.result_cap
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0595', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'ui.patron_search.result_cap',
        oils_i18n_gettext(
            'ui.patron_search.result_cap',
            'GUI: Cap results in Patron Search at this number.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron_search.result_cap',
            'So for example, if you search for John Doe, normally you would get'
            || ' at most 50 results.  This setting allows you to raise or lower'
            || ' that limit.',
            'coust',
            'description'
        ),
        'integer'
    );

-- Evergreen DB patch 0596.schema.vandelay-item-import-error-detail.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0596', :eg_version);

INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.status', oils_i18n_gettext('import.item.invalid.status', 'Invalid value for "status"', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.price', oils_i18n_gettext('import.item.invalid.price', 'Invalid value for "price"', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.deposit_amount', oils_i18n_gettext('import.item.invalid.deposit_amount', 'Invalid value for "deposit_amount"', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.owning_lib', oils_i18n_gettext('import.item.invalid.owning_lib', 'Invalid value for "owning_lib"', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.circ_lib', oils_i18n_gettext('import.item.invalid.circ_lib', 'Invalid value for "circ_lib"', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.copy_number', oils_i18n_gettext('import.item.invalid.copy_number', 'Invalid value for "copy_number"', 'vie', 'description') );
INSERT INTO vandelay.import_error ( code, description ) VALUES ( 
    'import.item.invalid.circ_as_type', oils_i18n_gettext('import.item.invalid.circ_as_type', 'Invalid value for "circ_as_type"', 'vie', 'description') );

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

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;
    tmp_str         TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id;

        -- Build the combined XPath

        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;

        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;

        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;

        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;

        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;

        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;

        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;

        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;

        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;

        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;

        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;

        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;

        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;

        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;

        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;

        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;

        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;


        xpath :=
            owning_lib      || '|' ||
            circ_lib        || '|' ||
            call_number     || '|' ||
            copy_number     || '|' ||
            status          || '|' ||
            location        || '|' ||
            circulate       || '|' ||
            deposit         || '|' ||
            deposit_amount  || '|' ||
            ref             || '|' ||
            holdable        || '|' ||
            price           || '|' ||
            barcode         || '|' ||
            circ_modifier   || '|' ||
            circ_as_type    || '|' ||
            alert_message   || '|' ||
            pub_note        || '|' ||
            priv_note       || '|' ||
            opac_visible;

        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id INT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, opac_vis TEXT )
        LOOP

            attr_set.import_error := NULL;
            attr_set.error_detail := NULL;
            attr_set.deposit_amount := NULL;
            attr_set.copy_number := NULL;
            attr_set.price := NULL;

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

            IF tmp_attr_set.circ_mod != '' THEN
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

            IF tmp_attr_set.cl != '' THEN

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
            opac_visible,
            import_error,
            error_detail
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
            item_data.opac_visible,
            item_data.import_error,
            item_data.error_detail
        );
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

-- Evergreen DB patch XXXX.schema.vandelay.bib_match_isxn_caseless.sql


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0597', :eg_version);

CREATE INDEX metabib_full_rec_isxn_caseless_idx
    ON metabib.real_full_rec (LOWER(value))
    WHERE tag IN ('020', '022', '024');


CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_ACCUM(tag || (COALESCE(subfield, ''))),
            ARRAY_ACCUM(value)
        )
        FROM (
            SELECT
                tag, subfield,
                CASE WHEN tag IN ('020', '022', '024') THEN  -- caseless
                    ARRAY_ACCUM(LOWER(value))::TEXT
                ELSE
                    ARRAY_ACCUM(value)::TEXT
                END AS value
                FROM vandelay.flatten_marc(record_xml)
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore

    IF node.negate THEN
        op := '<>';
    ELSE
        op := '=';
    END IF;

    caseless := FALSE;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := 'LEFT JOIN (SELECT *, ' || node.quality ||
        ' AS quality FROM metabib.';
    IF node.tag IS NOT NULL THEN
        jrow := jrow || 'full_rec) ' || my_alias || ' ON (' ||
            my_alias || '.record = bre.id AND ' || my_alias || '.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND ' || my_alias || '.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';

        IF caseless THEN
            jrow := jrow || 'LOWER(' || my_alias || '.value) ' || op;
        ELSE
            jrow := jrow || my_alias || '.value ' || op;
        END IF;

        jrow := jrow || ' ANY(($1->''' || tagkey || ''')::TEXT[])))';
    ELSE    -- svf
        jrow := jrow || 'record_attr) ' || my_alias || ' ON (' ||
            my_alias || '.id = bre.id AND (' ||
            my_alias || '.attrs->''' || node.svf ||
            ''' ' || op || ' $2->''' || node.svf || '''))';
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;

-- Evergreen DB patch 0598.schema.vandelay_one_match_per.sql
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0598', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    svf_rstore  HSTORE;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);
    svf_rstore := vandelay.extract_rec_attrs(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(match_set_id);

    query_ := 'SELECT DISTINCT(bre.id) AS record, ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT ARRAY_TO_STRING(
        ARRAY_ACCUM('COALESCE(n' || q::TEXT || '.quality, 0)'), ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n' ||
        'FROM biblio.record_entry bre ';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT ARRAY_TO_STRING(ARRAY_ACCUM(j), E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n' || 'WHERE ' || wq || ' AND not bre.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore, svf_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;

$$ LANGUAGE PLPGSQL;

-- Evergreen DB patch 0606.schema.czs_use_perm_column.sql
--
-- This adds a column to config.z3950_source called use_perm.
-- The idea is that if a permission is set for a given source,
-- then staff will need the referenced permission to use that
-- source.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0606', :eg_version);

ALTER TABLE config.z3950_source 
    ADD COLUMN use_perm INT REFERENCES permission.perm_list (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

COMMENT ON COLUMN config.z3950_source.use_perm IS $$
If set, this permission is required for the source to be listed in the staff
client Z39.50 interface.  Similar to permission.grp_tree.application_perm.
$$;

-- Evergreen DB patch 0608.data.vandelay-export-error-match-info.sql
--
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0608', :eg_version);

-- Add vqbr.import_error, vqbr.error_detail, and vqbr.matches.size to queue print output

UPDATE action_trigger.event_definition SET template = $$
[%- USE date -%]
<pre>
Queue ID: [% target.0.queue.id %]
Queue Name: [% target.0.queue.name %]
Queue Type: [% target.0.queue.queue_type %]
Complete? [% target.0.queue.complete %]

    [% FOR vqbr IN target %]
=-=-=
 Title of work    | [% helpers.get_queued_bib_attr('title',vqbr.attributes) %]
 Author of work   | [% helpers.get_queued_bib_attr('author',vqbr.attributes) %]
 Language of work | [% helpers.get_queued_bib_attr('language',vqbr.attributes) %]
 Pagination       | [% helpers.get_queued_bib_attr('pagination',vqbr.attributes) %]
 ISBN             | [% helpers.get_queued_bib_attr('isbn',vqbr.attributes) %]
 ISSN             | [% helpers.get_queued_bib_attr('issn',vqbr.attributes) %]
 Price            | [% helpers.get_queued_bib_attr('price',vqbr.attributes) %]
 Accession Number | [% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) %]
 TCN Value        | [% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) %]
 TCN Source       | [% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) %]
 Internal ID      | [% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) %]
 Publisher        | [% helpers.get_queued_bib_attr('publisher',vqbr.attributes) %]
 Publication Date | [% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) %]
 Edition          | [% helpers.get_queued_bib_attr('edition',vqbr.attributes) %]
 Item Barcode     | [% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) %]
 Import Error     | [% vqbr.import_error %]
 Error Detail     | [% vqbr.error_detail %]
 Match Count      | [% vqbr.matches.size %]

    [% END %]
</pre>
$$
WHERE id = 39;


-- Do the same for the CVS version

UPDATE action_trigger.event_definition SET template = $$
[%- USE date -%]
"Title of work","Author of work","Language of work","Pagination","ISBN","ISSN","Price","Accession Number","TCN Value","TCN Source","Internal ID","Publisher","Publication Date","Edition","Item Barcode","Import Error","Error Detail","Match Count"
[% FOR vqbr IN target %]"[% helpers.get_queued_bib_attr('title',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('author',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('language',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('pagination',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('isbn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('issn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('price',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('rec_identifier',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_tcn',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_tcn_source',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('eg_identifier',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('publisher',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('pubdate',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('edition',vqbr.attributes) | replace('"', '""') %]","[% helpers.get_queued_bib_attr('item_barcode',vqbr.attributes) | replace('"', '""') %]","[% vqbr.import_error | replace('"', '""') %]","[% vqbr.error_detail | replace('"', '""') %]","[% vqbr.matches.size %]"
[% END %]
$$
WHERE id = 40;

-- Add matches to the env for both
INSERT INTO action_trigger.environment (event_def, path) VALUES (39, 'matches');
INSERT INTO action_trigger.environment (event_def, path) VALUES (40, 'matches');


-- Evergreen DB patch XXXX.data.acq-copy-creator-from-receiver.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0609', :eg_version);

ALTER TABLE acq.lineitem_detail 
    ADD COLUMN receiver	INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED;


-- Evergreen DB patch XXXX.data.acq-copy-creator-from-receiver.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0610', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'acq.copy_creator_uses_receiver',
    oils_i18n_gettext( 
        'acq.copy_creator_uses_receiver',
        'Acq: Set copy creator as receiver',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'acq.copy_creator_uses_receiver',
        'When receiving a copy in acquisitions, set the copy "creator" to be the staff that received the copy',
        'coust',
        'label'
    ),
    'bool'
);

-- Evergreen DB patch 0611.data.magic_macros.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0611', :eg_version);

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
(
        'circ.staff_client.receipt.header_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.header_text',
            'Receipt Template: Content of header_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.header_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(header_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.footer_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.footer_text',
            'Receipt Template: Content of footer_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.footer_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(footer_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.notice_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.notice_text',
            'Receipt Template: Content of notice_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.notice_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(notice_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.alert_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.alert_text',
            'Receipt Template: Content of alert_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.alert_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(alert_text)%',
            'coust',
            'description'
        ),
        'string'
    )
,(
        'circ.staff_client.receipt.event_text',
        oils_i18n_gettext(
            'circ.staff_client.receipt.event_text',
            'Receipt Template: Content of event_text include',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.staff_client.receipt.event_text',
            'Text/HTML/Macros to be inserted into receipt templates in place of %INCLUDE(event_text)%',
            'coust',
            'description'
        ),
        'string'
    );

-- Evergreen DB patch 0612.schema.authority_overlay_protection.sql
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0612', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade

-- Function to generate an ephemeral overlay template from an authority record
CREATE OR REPLACE FUNCTION authority.generate_overlay_template (source_xml TEXT) RETURNS TEXT AS $f$
DECLARE
    cset                INT;
    main_entry          authority.control_set_authority_field%ROWTYPE;
    bib_field           authority.control_set_bib_field%ROWTYPE;
    auth_id             INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', source_xml)::INT;
    replace_data        XML[] DEFAULT '{}'::XML[];
    replace_rules       TEXT[] DEFAULT '{}'::TEXT[];
    auth_field          XML[];
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
                    SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marc::XML)::TEXT[])
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

    FOR main_entry IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP
        auth_field := XPATH('//*[@tag="'||main_entry.tag||'"][1]',source_xml::XML);
        IF ARRAY_LENGTH(auth_field,1) > 0 THEN
            FOR bib_field IN SELECT * FROM authority.control_set_bib_field WHERE authority_field = main_entry.id LOOP
                replace_data := replace_data || XMLELEMENT( name datafield, XMLATTRIBUTES(bib_field.tag AS tag), XPATH('//*[local-name()="subfield"]',auth_field[1])::XML[]);
                replace_rules := replace_rules || ( bib_field.tag || main_entry.sf_list || E'[0~\\)' || auth_id || '$]' );
            END LOOP;
            EXIT;
        END IF;
    END LOOP;

    RETURN XMLELEMENT(
        name record,
        XMLATTRIBUTES('http://www.loc.gov/MARC21/slim' AS xmlns),
        XMLELEMENT( name leader, '00881nam a2200193   4500'),
        replace_data,
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



-- Evergreen DB patch 0613.schema.vandelay_isxn_normalization.sql
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0613', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $func$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_ACCUM(tag || (COALESCE(subfield, ''))),
            ARRAY_ACCUM(value)
        )
        FROM (
            SELECT  tag, subfield, ARRAY_ACCUM(value)::TEXT AS value
              FROM  (SELECT tag,
                            subfield,
                            CASE WHEN tag = '020' THEN -- caseless -- isbn
                                LOWER((REGEXP_MATCHES(value,$$^(\S{10,17})$$))[1] || '%')
                            WHEN tag = '022' THEN -- caseless -- issn
                                LOWER((REGEXP_MATCHES(value,$$^(\S{4}[- ]?\S{4})$$))[1] || '%')
                            WHEN tag = '024' THEN -- caseless -- upc (other)
                                LOWER(value || '%')
                            ELSE
                                value
                            END AS value
                      FROM  vandelay.flatten_marc(record_xml)) x
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore

    caseless := FALSE;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    IF node.negate THEN
        IF caseless THEN
            op := 'NOT LIKE';
        ELSE
            op := '<>';
        END IF;
    ELSE
        IF caseless THEN
            op := 'LIKE';
        ELSE
            op := '=';
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := 'LEFT JOIN (SELECT *, ' || node.quality ||
        ' AS quality FROM metabib.';
    IF node.tag IS NOT NULL THEN
        jrow := jrow || 'full_rec) ' || my_alias || ' ON (' ||
            my_alias || '.record = bre.id AND ' || my_alias || '.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND ' || my_alias || '.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';

        IF caseless THEN
            jrow := jrow || 'LOWER(' || my_alias || '.value) ' || op;
        ELSE
            jrow := jrow || my_alias || '.value ' || op;
        END IF;

        jrow := jrow || ' ANY(($1->''' || tagkey || ''')::TEXT[])))';
    ELSE    -- svf
        jrow := jrow || 'record_attr) ' || my_alias || ' ON (' ||
            my_alias || '.id = bre.id AND (' ||
            my_alias || '.attrs->''' || node.svf ||
            ''' ' || op || ' $2->''' || node.svf || '''))';
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;



-- Evergreen DB patch XXXX.schema.generic-mapping-index-normalizer.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0615', :eg_version);

-- evergreen.generic_map_normalizer 

CREATE OR REPLACE FUNCTION evergreen.generic_map_normalizer ( TEXT, TEXT ) RETURNS TEXT AS $f$
my $string = shift;
my %map;

my $default = $string;

$_ = shift;
while (/^\s*?(.*?)\s*?=>\s*?(\S+)\s*/) {
    if ($1 eq '') {
        $default = $2;
    } else {
        $map{$2} = [split(/\s*,\s*/, $1)];
    }
    $_ = $';
}

for my $key ( keys %map ) {
    return $key if (grep { $_ eq $string } @{ $map{$key} });
}

return $default;

$f$ LANGUAGE PLPERLU;

-- evergreen.generic_map_normalizer 

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
    'Generic Mapping Normalizer', 
    'Map values or sets of values to new values',
    'generic_map_normalizer', 
    1
);


SELECT evergreen.upgrade_deps_block_check('0616', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_prox_update () RETURNS TRIGGER as $$
BEGIN


IF TG_OP = 'DELETE' THEN

    DELETE FROM actor.org_unit_proximity WHERE (from_org = OLD.id or to_org= OLD.id);

END IF;

IF TG_OP = 'UPDATE' THEN

    IF NEW.parent_ou <> OLD.parent_ou THEN

        DELETE FROM actor.org_unit_proximity WHERE (from_org = OLD.id or to_org= OLD.id);
            INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
            SELECT  l.id, r.id, actor.org_unit_proximity(l.id,r.id)
                FROM  actor.org_unit l, actor.org_unit r
                WHERE (l.id = NEW.id or r.id = NEW.id);

    END IF;

END IF;

IF TG_OP = 'INSERT' THEN

     INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
     SELECT  l.id, r.id, actor.org_unit_proximity(l.id,r.id)
         FROM  actor.org_unit l, actor.org_unit r
         WHERE (l.id = NEW.id or r.id = NEW.id);

END IF;

RETURN null;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER proximity_update_tgr AFTER INSERT OR UPDATE OR DELETE ON actor.org_unit FOR EACH ROW EXECUTE PROCEDURE actor.org_unit_prox_update ();


SELECT evergreen.upgrade_deps_block_check('0617', :eg_version);

-- add notify columns to booking.reservation
ALTER TABLE booking.reservation
  ADD COLUMN email_notify BOOLEAN NOT NULL DEFAULT FALSE;

-- create the hook and validator
INSERT INTO action_trigger.hook (key, core_type, description, passive)
  VALUES ('reservation.available', 'bresv', 'A reservation is available for pickup', false);
INSERT INTO action_trigger.validator (module, description)
  VALUES ('ReservationIsAvailable','Checked that a reserved resource is available for checkout');

-- create org unit setting to toggle checkbox display
INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
  VALUES ('booking.allow_email_notify', 'booking.allow_email_notify', 'Permit email notification when a reservation is ready for pickup.', 'bool');


SELECT evergreen.upgrade_deps_block_check('0618', :eg_version);

UPDATE config.org_unit_setting_type SET description = E'The Regular Expression for validation on the day_phone field in patron registration. Note: The first capture group will be used for the "last 4 digits of phone number" feature, if enabled. Ex: "[2-9]\\d{2}-\\d{3}-(\\d{4})( x\\d+)?" will ignore the extension on a NANP number.' WHERE name = 'ui.patron.edit.au.day_phone.regex';

UPDATE config.org_unit_setting_type SET description = 'The Regular Expression for validation on phone fields in patron registration. Applies to all phone fields without their own setting. NOTE: See description of the day_phone regex for important information about capture groups with it.' WHERE name = 'ui.patron.edit.phone.regex';

UPDATE config.org_unit_setting_type SET description = oils_i18n_gettext('patron.password.use_phone', 'By default, use the last 4 alphanumeric characters of the patrons phone number as the default password when creating new users.  The exact characters used may be configured via the "GUI: Regex for day_phone field on patron registration" setting.', 'coust', 'description') WHERE name = 'patron.password.use_phone';

-- Evergreen DB patch 0619.schema.au_last_update_time.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0619', :eg_version);

-- Add new column last_update_time to actor.usr, with trigger to maintain it
-- Add corresponding new column to auditor.actor_usr_history

ALTER TABLE actor.usr
	ADD COLUMN last_update_time TIMESTAMPTZ;

ALTER TABLE auditor.actor_usr_history
	ADD COLUMN last_update_time TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION actor.au_updated()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_update_time := now();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER au_update_trig
	BEFORE INSERT OR UPDATE ON actor.usr
	FOR EACH ROW EXECUTE PROCEDURE actor.au_updated();

-- Evergreen DB patch XXXX.data.opac_payment_history_age_limit.sql


SELECT evergreen.upgrade_deps_block_check('0621', :eg_version);

INSERT into config.org_unit_setting_type (name, label, description, datatype)
VALUES (
    'opac.payment_history_age_limit',
    oils_i18n_gettext('opac.payment_history_age_limit',
        'OPAC: Payment History Age Limit', 'coust', 'label'),
    oils_i18n_gettext('opac.payment_history_age_limit',
        'The OPAC should not display payments by patrons that are older than any interval defined here.', 'coust', 'label'),
    'interval'
);

-- Updates config.org_unit_setting_type to remove the old tag prefixes for once 
-- groups have been added.
--

SELECT evergreen.upgrade_deps_block_check('0622', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
('sys', oils_i18n_gettext('config.settings_group.system', 'System', 'coust', 'label')),
('gui', oils_i18n_gettext('config.settings_group.gui', 'GUI', 'coust', 'label')),
('lib', oils_i18n_gettext('config.settings_group.lib', 'Library', 'coust', 'label')),
('sec', oils_i18n_gettext('config.settings_group.sec', 'Security', 'coust', 'label')),
('cat', oils_i18n_gettext('config.settings_group.cat', 'Cataloging', 'coust', 'label')),
('holds', oils_i18n_gettext('config.settings_group.holds', 'Holds', 'coust', 'label')),
('circ', oils_i18n_gettext('config.settings_group.circulation', 'Circulation', 'coust', 'label')),
('self', oils_i18n_gettext('config.settings_group.self', 'Self Check', 'coust', 'label')),
('opac', oils_i18n_gettext('config.settings_group.opac', 'OPAC', 'coust', 'label')),
('prog', oils_i18n_gettext('config.settings_group.program', 'Program', 'coust', 'label')),
('glob', oils_i18n_gettext('config.settings_group.global', 'Global', 'coust', 'label')),
('finance', oils_i18n_gettext('config.settings_group.finances', 'Finances', 'coust', 'label')),
('credit', oils_i18n_gettext('config.settings_group.ccp', 'Credit Card Processing', 'coust', 'label')),
('serial', oils_i18n_gettext('config.settings_group.serial', 'Serials', 'coust', 'label')),
('recall', oils_i18n_gettext('config.settings_group.recall', 'Recalls', 'coust', 'label')),
('booking', oils_i18n_gettext('config.settings_group.booking', 'Booking', 'coust', 'label')),
('offline', oils_i18n_gettext('config.settings_group.offline', 'Offline', 'coust', 'label')),
('receipt_template', oils_i18n_gettext('config.settings_group.receipt_template', 'Receipt Template', 'coust', 'label'));

UPDATE config.org_unit_setting_type SET grp = 'lib', label='Set copy creator as receiver' WHERE name = 'acq.copy_creator_uses_receiver';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.default_circ_modifier';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.default_copy_location';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'acq.fund.balance_limit.block';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'acq.fund.balance_limit.warn';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.holds.allow_holds_from_purchase_request';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.tmp_barcode_prefix';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'acq.tmp_callnumber_prefix';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.opac_timeout';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.persistent_login_interval';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'auth.staff_timeout';
UPDATE config.org_unit_setting_type SET grp = 'booking' WHERE name = 'booking.allow_email_notify';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'cat.bib.alert_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Delete bib if all copies are deleted via Acquisitions lineitem cancellation.' WHERE name = 'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'cat.bib.keep_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Default Classification Scheme' WHERE name = 'cat.default_classification_scheme';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Default copy status (fast add)' WHERE name = 'cat.default_copy_status_fast';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Default copy status (normal)' WHERE name = 'cat.default_copy_status_normal';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'cat.default_item_price';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine and pocket label font family' WHERE name = 'cat.label.font.family';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine and pocket label font size' WHERE name = 'cat.label.font.size';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine and pocket label font weight' WHERE name = 'cat.label.font.weight';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Defines the control number identifier used in 003 and 035 fields.' WHERE name = 'cat.marc_control_number_identifier';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine label maximum lines' WHERE name = 'cat.spine.line.height';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine label left margin' WHERE name = 'cat.spine.line.margin';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Spine label line width' WHERE name = 'cat.spine.line.width';
UPDATE config.org_unit_setting_type SET grp = 'cat', label='Delete volume with last copy' WHERE name = 'cat.volume.delete_on_empty';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Toggle off the patron summary sidebar after first view.' WHERE name = 'circ.auto_hide_patron_summary';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Block Renewal of Items Needed for Holds' WHERE name = 'circ.block_renews_for_holds';
UPDATE config.org_unit_setting_type SET grp = 'booking', label='Elbow room' WHERE name = 'circ.booking_reservation.default_elbow_room';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.charge_lost_on_zero';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.charge_on_damaged';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_auto_renew_age';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_fills_related_hold';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.checkout_fills_related_hold_exact_match_only';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.claim_never_checked_out.mark_missing';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.claim_return.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.damaged.void_ovedue';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.damaged_item_processing_fee';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Do not include outstanding Claims Returned circulations in lump sum tallies in Patron Display.' WHERE name = 'circ.do_not_tally_claims_returned';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Hard boundary' WHERE name = 'circ.hold_boundary.hard';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Soft boundary' WHERE name = 'circ.hold_boundary.soft';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Expire Alert Interval' WHERE name = 'circ.hold_expire_alert_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Expire Interval' WHERE name = 'circ.hold_expire_interval';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.hold_shelf_status_delay';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Soft stalling interval' WHERE name = 'circ.hold_stalling.soft';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Hard stalling interval' WHERE name = 'circ.hold_stalling_hard';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Use Active Date for Age Protection' WHERE name = 'circ.holds.age_protect.active_date';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Behind Desk Pickup Supported' WHERE name = 'circ.holds.behind_desk_pickup_supported';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Canceled holds display age' WHERE name = 'circ.holds.canceled.display_age';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Canceled holds display count' WHERE name = 'circ.holds.canceled.display_count';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Clear shelf copy status' WHERE name = 'circ.holds.clear_shelf.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Bypass hold capture during clear shelf process' WHERE name = 'circ.holds.clear_shelf.no_capture_holds';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Default Estimated Wait' WHERE name = 'circ.holds.default_estimated_wait_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.default_shelf_expire_interval';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Block hold request if hold recipient privileges have expired' WHERE name = 'circ.holds.expired_patron_block';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Has Local Copy Alert' WHERE name = 'circ.holds.hold_has_copy_at.alert';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Has Local Copy Block' WHERE name = 'circ.holds.hold_has_copy_at.block';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Maximum library target attempts' WHERE name = 'circ.holds.max_org_unit_target_loops';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Minimum Estimated Wait' WHERE name = 'circ.holds.min_estimated_wait_interval';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Org Unit Target Weight' WHERE name = 'circ.holds.org_unit_target_weight';
UPDATE config.org_unit_setting_type SET grp = 'recall', label='An array of fine amount, fine interval, and maximum fine.' WHERE name = 'circ.holds.recall_fine_rules';
UPDATE config.org_unit_setting_type SET grp = 'recall', label='Truncated loan period.' WHERE name = 'circ.holds.recall_return_interval';
UPDATE config.org_unit_setting_type SET grp = 'recall', label='Circulation duration that triggers a recall.' WHERE name = 'circ.holds.recall_threshold';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Use weight-based hold targeting' WHERE name = 'circ.holds.target_holds_by_org_unit_weight';
UPDATE config.org_unit_setting_type SET grp = 'holds' WHERE name = 'circ.holds.target_skip_me';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='Reset request time on un-cancel' WHERE name = 'circ.holds.uncancel.reset_request_time';
UPDATE config.org_unit_setting_type SET grp = 'holds', label='FIFO' WHERE name = 'circ.holds_fifo';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'circ.item_checkout_history.max';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Lost Checkin Generates New Overdues' WHERE name = 'circ.lost.generate_overdue_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Lost items usable on checkin' WHERE name = 'circ.lost_immediately_available';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'circ.lost_materials_processing_fee';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Void lost max interval' WHERE name = 'circ.max_accept_return_of_lost';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Cap Max Fine at Item Price' WHERE name = 'circ.max_fine.cap_at_price';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.max_patron_claim_return_count';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Item Status for Missing Pieces' WHERE name = 'circ.missing_pieces.copy_status';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'circ.obscure_dob';
UPDATE config.org_unit_setting_type SET grp = 'offline', label='Skip offline checkin if newer item Status Changed Time.' WHERE name = 'circ.offline.skip_checkin_if_newer_status_changed_time';
UPDATE config.org_unit_setting_type SET grp = 'offline', label='Skip offline checkout if newer item Status Changed Time.' WHERE name = 'circ.offline.skip_checkout_if_newer_status_changed_time';
UPDATE config.org_unit_setting_type SET grp = 'offline', label='Skip offline renewal if newer item Status Changed Time.' WHERE name = 'circ.offline.skip_renew_if_newer_status_changed_time';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Offline: Patron Usernames Allowed' WHERE name = 'circ.offline.username_allowed';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Maximum concurrently active self-serve password reset requests per user' WHERE name = 'circ.password_reset_request_per_user_limit';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Require matching email address for password reset requests' WHERE name = 'circ.password_reset_request_requires_matching_email';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Maximum concurrently active self-serve password reset requests' WHERE name = 'circ.password_reset_request_throttle';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Self-serve password reset request time-to-live' WHERE name = 'circ.password_reset_request_time_to_live';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Registration: Cloned patrons get address copy' WHERE name = 'circ.patron_edit.clone.copy_address';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.patron_invalid_address_apply_penalty';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.pre_cat_copy_circ_lib';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'circ.reshelving_complete.interval';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Restore overdues on lost item return' WHERE name = 'circ.restore_overdue_on_lost_return';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Pop-up alert for errors' WHERE name = 'circ.selfcheck.alert.popup';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Audio Alerts' WHERE name = 'circ.selfcheck.alert.sound';
UPDATE config.org_unit_setting_type SET grp = 'self' WHERE name = 'circ.selfcheck.auto_override_checkout_events';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Block copy checkout status' WHERE name = 'circ.selfcheck.block_checkout_on_copy_status';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Patron Login Timeout (in seconds)' WHERE name = 'circ.selfcheck.patron_login_timeout';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Require Patron Password' WHERE name = 'circ.selfcheck.patron_password_required';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Require patron password' WHERE name = 'circ.selfcheck.require_patron_password';
UPDATE config.org_unit_setting_type SET grp = 'self', label='Workstation Required' WHERE name = 'circ.selfcheck.workstation_required';
UPDATE config.org_unit_setting_type SET grp = 'circ' WHERE name = 'circ.staff_client.actor_on_checkout';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'circ.staff_client.do_not_auto_attempt_print';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of alert_text include' WHERE name = 'circ.staff_client.receipt.alert_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of event_text include' WHERE name = 'circ.staff_client.receipt.event_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of footer_text include' WHERE name = 'circ.staff_client.receipt.footer_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of header_text include' WHERE name = 'circ.staff_client.receipt.header_text';
UPDATE config.org_unit_setting_type SET grp = 'receipt_template', label='Content of notice_text include' WHERE name = 'circ.staff_client.receipt.notice_text';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Minimum Transit Checkin Interval' WHERE name = 'circ.transit.min_checkin_interval';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Merge Deactivate Card' WHERE name = 'circ.user_merge.deactivate_cards';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Merge Address Delete' WHERE name = 'circ.user_merge.delete_addresses';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Patron Merge Barcode Delete' WHERE name = 'circ.user_merge.delete_cards';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Void lost item billing when returned' WHERE name = 'circ.void_lost_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Void processing fee on lost item return' WHERE name = 'circ.void_lost_proc_fee_on_checkin';
UPDATE config.org_unit_setting_type SET grp = 'finance', label='Void overdue fines when items are marked lost' WHERE name = 'circ.void_overdue_on_lost';
UPDATE config.org_unit_setting_type SET grp = 'finance' WHERE name = 'credit.payments.allow';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Enable AuthorizeNet payments' WHERE name = 'credit.processor.authorizenet.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet login' WHERE name = 'credit.processor.authorizenet.login';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet password' WHERE name = 'credit.processor.authorizenet.password';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet server' WHERE name = 'credit.processor.authorizenet.server';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='AuthorizeNet test mode' WHERE name = 'credit.processor.authorizenet.testmode';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Name default credit processor' WHERE name = 'credit.processor.default';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Enable PayflowPro payments' WHERE name = 'credit.processor.payflowpro.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro login/merchant ID' WHERE name = 'credit.processor.payflowpro.login';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro partner' WHERE name = 'credit.processor.payflowpro.partner';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro password' WHERE name = 'credit.processor.payflowpro.password';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro test mode' WHERE name = 'credit.processor.payflowpro.testmode';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayflowPro vendor' WHERE name = 'credit.processor.payflowpro.vendor';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='Enable PayPal payments' WHERE name = 'credit.processor.paypal.enabled';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal login' WHERE name = 'credit.processor.paypal.login';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal password' WHERE name = 'credit.processor.paypal.password';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal signature' WHERE name = 'credit.processor.paypal.signature';
UPDATE config.org_unit_setting_type SET grp = 'credit', label='PayPal test mode' WHERE name = 'credit.processor.paypal.testmode';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Format Dates with this pattern.' WHERE name = 'format.date';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Format Times with this pattern.' WHERE name = 'format.time';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'global.default_locale';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'global.juvenile_age_threshold';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'global.password_regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Disable the ability to save list column configurations locally.' WHERE name = 'gui.disable_local_save_columns';
UPDATE config.org_unit_setting_type SET grp = 'lib', label='Courier Code' WHERE name = 'lib.courier_code';
UPDATE config.org_unit_setting_type SET grp = 'lib' WHERE name = 'notice.telephony.callfile_lines';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Allow pending addresses' WHERE name = 'opac.allow_pending_address';
UPDATE config.org_unit_setting_type SET grp = 'glob' WHERE name = 'opac.barcode_regex';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Use fully compressed serial holdings' WHERE name = 'opac.fully_compressed_serial_holdings';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Org Unit Hiding Depth' WHERE name = 'opac.org_unit_hiding.depth';
UPDATE config.org_unit_setting_type SET grp = 'opac', label='Payment History Age Limit' WHERE name = 'opac.payment_history_age_limit';
UPDATE config.org_unit_setting_type SET grp = 'prog' WHERE name = 'org.bounced_emails';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Patron Opt-In Boundary' WHERE name = 'org.patron_opt_boundary';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Patron Opt-In Default' WHERE name = 'org.patron_opt_default';
UPDATE config.org_unit_setting_type SET grp = 'sec' WHERE name = 'patron.password.use_phone';
UPDATE config.org_unit_setting_type SET grp = 'serial', label='Previous Issuance Copy Location' WHERE name = 'serial.prev_issuance_copy_location';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Work Log: Maximum Patrons Logged' WHERE name = 'ui.admin.patron_log.max_entries';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Work Log: Maximum Actions Logged' WHERE name = 'ui.admin.work_log.max_entries';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Horizontal layout for Volume/Copy Creator/Editor.' WHERE name = 'ui.cat.volume_copy_editor.horizontal';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Uncheck bills by default in the patron billing interface' WHERE name = 'ui.circ.billing.uncheck_bills_and_unfocus_payment_box';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Record In-House Use: Maximum # of uses allowed per entry.' WHERE name = 'ui.circ.in_house_use.entry_cap';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Record In-House Use: # of uses threshold for Are You Sure? dialog.' WHERE name = 'ui.circ.in_house_use.entry_warn';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.patron_summary.horizontal';
UPDATE config.org_unit_setting_type SET grp = 'gui' WHERE name = 'ui.circ.show_billing_tab_on_bills';
UPDATE config.org_unit_setting_type SET grp = 'circ', label='Suppress popup-dialogs during check-in.' WHERE name = 'ui.circ.suppress_checkin_popups';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Button bar' WHERE name = 'ui.general.button_bar';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default Hotkeyset' WHERE name = 'ui.general.hotkeyset';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Idle timeout' WHERE name = 'ui.general.idle_timeout';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default Country for New Addresses in Patron Editor' WHERE name = 'ui.patron.default_country';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default Ident Type for Patron Registration' WHERE name = 'ui.patron.default_ident_type';
UPDATE config.org_unit_setting_type SET grp = 'sec', label='Default level of patrons'' internet access' WHERE name = 'ui.patron.default_inet_access_level';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show active field on patron registration' WHERE name = 'ui.patron.edit.au.active.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest active field on patron registration' WHERE name = 'ui.patron.edit.au.active.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show alert_message field on patron registration' WHERE name = 'ui.patron.edit.au.alert_message.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest alert_message field on patron registration' WHERE name = 'ui.patron.edit.au.alert_message.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show alias field on patron registration' WHERE name = 'ui.patron.edit.au.alias.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest alias field on patron registration' WHERE name = 'ui.patron.edit.au.alias.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show barred field on patron registration' WHERE name = 'ui.patron.edit.au.barred.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest barred field on patron registration' WHERE name = 'ui.patron.edit.au.barred.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show claims_never_checked_out_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_never_checked_out_count.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest claims_never_checked_out_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_never_checked_out_count.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show claims_returned_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_returned_count.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest claims_returned_count field on patron registration' WHERE name = 'ui.patron.edit.au.claims_returned_count.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest day_phone field on patron registration' WHERE name = 'ui.patron.edit.au.day_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show calendar widget for dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.calendar';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest dob field on patron registration' WHERE name = 'ui.patron.edit.au.dob.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for email field on patron registration' WHERE name = 'ui.patron.edit.au.email.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for email field on patron registration' WHERE name = 'ui.patron.edit.au.email.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require email field on patron registration' WHERE name = 'ui.patron.edit.au.email.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show email field on patron registration' WHERE name = 'ui.patron.edit.au.email.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest email field on patron registration' WHERE name = 'ui.patron.edit.au.email.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest evening_phone field on patron registration' WHERE name = 'ui.patron.edit.au.evening_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show ident_value field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest ident_value field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show ident_value2 field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value2.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest ident_value2 field on patron registration' WHERE name = 'ui.patron.edit.au.ident_value2.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show juvenile field on patron registration' WHERE name = 'ui.patron.edit.au.juvenile.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest juvenile field on patron registration' WHERE name = 'ui.patron.edit.au.juvenile.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show master_account field on patron registration' WHERE name = 'ui.patron.edit.au.master_account.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest master_account field on patron registration' WHERE name = 'ui.patron.edit.au.master_account.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest other_phone field on patron registration' WHERE name = 'ui.patron.edit.au.other_phone.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show second_given_name field on patron registration' WHERE name = 'ui.patron.edit.au.second_given_name.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest second_given_name field on patron registration' WHERE name = 'ui.patron.edit.au.second_given_name.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Show suffix field on patron registration' WHERE name = 'ui.patron.edit.au.suffix.show';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Suggest suffix field on patron registration' WHERE name = 'ui.patron.edit.au.suffix.suggest';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require county field on patron registration' WHERE name = 'ui.patron.edit.aua.county.require';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for post_code field on patron registration' WHERE name = 'ui.patron.edit.aua.post_code.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for post_code field on patron registration' WHERE name = 'ui.patron.edit.aua.post_code.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Default showing suggested patron registration fields' WHERE name = 'ui.patron.edit.default_suggested';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Example for phone fields on patron registration' WHERE name = 'ui.patron.edit.phone.example';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Regex for phone fields on patron registration' WHERE name = 'ui.patron.edit.phone.regex';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require at least one address for Patron Registration' WHERE name = 'ui.patron.registration.require_address';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Cap results in Patron Search at this number.' WHERE name = 'ui.patron_search.result_cap';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Require staff initials for entry/edit of item/patron/penalty notes/messages.' WHERE name = 'ui.staff.require_initials';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='Unified Volume/Item Creator/Editor' WHERE name = 'ui.unified_volume_copy_editor';
UPDATE config.org_unit_setting_type SET grp = 'gui', label='URL for remote directory containing list column settings.' WHERE name = 'url.remote_column_settings';




SELECT evergreen.upgrade_deps_block_check('0623', :eg_version);


CREATE TABLE config.org_unit_setting_type_log (
    id              BIGSERIAL   PRIMARY KEY,
    date_applied    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    org             INT         REFERENCES actor.org_unit (id),
    original_value  TEXT,
    new_value       TEXT,
    field_name      TEXT      REFERENCES config.org_unit_setting_type (name)
);

-- Log each change in oust to oustl, so admins can see what they messed up if someting stops working.
CREATE OR REPLACE FUNCTION ous_change_log() RETURNS TRIGGER AS $ous_change_log$
    DECLARE
    original TEXT;
    BEGIN
        -- Check for which setting is being updated, and log it.
        SELECT INTO original value FROM actor.org_unit_setting WHERE name = NEW.name AND org_unit = NEW.org_unit;
                
        INSERT INTO config.org_unit_setting_type_log (org,original_value,new_value,field_name) VALUES (NEW.org_unit, original, NEW.value, NEW.name);
        
        RETURN NEW;
    END;
$ous_change_log$ LANGUAGE plpgsql;    

CREATE TRIGGER log_ous_change
    BEFORE INSERT OR UPDATE ON actor.org_unit_setting
    FOR EACH ROW EXECUTE PROCEDURE ous_change_log();

CREATE OR REPLACE FUNCTION ous_delete_log() RETURNS TRIGGER AS $ous_delete_log$
    DECLARE
    original TEXT;
    BEGIN
        -- Check for which setting is being updated, and log it.
        SELECT INTO original value FROM actor.org_unit_setting WHERE name = OLD.name AND org_unit = OLD.org_unit;
                
        INSERT INTO config.org_unit_setting_type_log (org,original_value,new_value,field_name) VALUES (OLD.org_unit, original, 'null', OLD.name);
        
        RETURN OLD;
    END;
$ous_delete_log$ LANGUAGE plpgsql;    

CREATE TRIGGER log_ous_del
    BEFORE DELETE ON actor.org_unit_setting
    FOR EACH ROW EXECUTE PROCEDURE ous_delete_log();

-- Evergreen DB patch 0625.data.opac_staff_saved_search_size.sql


SELECT evergreen.upgrade_deps_block_check('0625', :eg_version);

INSERT into config.org_unit_setting_type (name, grp, label, description, datatype)
VALUES (
    'opac.staff_saved_search.size', 'opac',
    oils_i18n_gettext('opac.staff_saved_search.size',
        'OPAC: Number of staff client saved searches to display on left side of results and record details pages', 'coust', 'label'),
    oils_i18n_gettext('opac.staff_saved_search.size',
        'If unset, the OPAC (only when wrapped in the staff client!) will default to showing you your ten most recent searches on the left side of the results and record details pages.  If you actually don''t want to see this feature at all, set this value to zero at the top of your organizational tree.', 'coust', 'description'),
    'integer'
);

-- Evergreen DB patch 0626.schema.bookbag-goodies.sql


SELECT evergreen.upgrade_deps_block_check('0626', :eg_version);

ALTER TABLE container.biblio_record_entry_bucket
    ADD COLUMN description TEXT;

ALTER TABLE container.call_number_bucket
    ADD COLUMN description TEXT;

ALTER TABLE container.copy_bucket
    ADD COLUMN description TEXT;

ALTER TABLE container.user_bucket
    ADD COLUMN description TEXT;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'container.biblio_record_entry_bucket.csv',
    'cbreb',
    oils_i18n_gettext(
        'container.biblio_record_entry_bucket.csv',
        'Produce a CSV file representing a bookbag',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.reactor (module, description)
VALUES (
    'ContainerCSV',
    oils_i18n_gettext(
        'ContainerCSV',
        'Facilitates produce a CSV file representing a bookbag by introducing an "items" variable into the TT environment, sorted as dictated according to user params',
        'atr',
        'description'
    )
);

INSERT INTO action_trigger.event_definition (
    id, active, owner,
    name, hook, reactor,
    validator, template
) VALUES (
    48, TRUE, 1,
    'Bookbag CSV', 'container.biblio_record_entry_bucket.csv', 'ContainerCSV',
    'NOOP_True',
$$
[%-
# target is the bookbag itself. The 'items' variable does not need to be in
# the environment because a special reactor will take care of filling it in.

FOR item IN items;
    bibxml = helpers.xml_doc(item.target_biblio_record_entry.marc);
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;

    helpers.csv_datum(title) %],[% helpers.csv_datum(author) %],[% FOR note IN item.notes; helpers.csv_datum(note.note); ","; END; "\n";
END -%]
$$
);

-- Evergreen DB patch 0627.data.patron-password-reset-msg.sql
--
-- Updates password reset template to match TPAC reset form
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0627', :eg_version);

UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%- user = target.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || user.home_ou.email || default_sender %]
Subject: [% user.home_ou.name %]: library account password reset request

You have received this message because you, or somebody else, requested a reset
of your library system password. If you did not request a reset of your library
system password, just ignore this message and your current password will
continue to work.

If you did request a reset of your library system password, please perform
the following steps to continue the process of resetting your password:

1. Open the following link in a web browser: https://[% params.hostname %]/eg/opac/password_reset/[% target.uuid %]
The browser displays a password reset form.

2. Enter your new password in the password reset form in the browser. You must
enter the password twice to ensure that you do not make a mistake. If the
passwords match, you will then be able to log in to your library system account
with the new password.

$$
WHERE id = 20; -- Password reset request notification


SELECT evergreen.upgrade_deps_block_check('0630', :eg_version);

INSERT into config.org_unit_setting_type (name, grp, label, description, datatype) VALUES
( 'circ.transit.suppress_hold', 'circ',
    oils_i18n_gettext('circ.transit.suppress_hold',
        'Suppress Hold Transits Group',
        'coust', 'label'),
    oils_i18n_gettext('circ.transit.suppress_hold',
        'If set to a non-empty value, Hold Transits will be suppressed between this OU and others with the same value. If set to an empty value, transits will not be suppressed.',
        'coust', 'description'),
    'string')
,( 'circ.transit.suppress_non_hold', 'circ',
    oils_i18n_gettext('circ.transit.suppress_non_hold',
        'Suppress Non-Hold Transits Group',
        'coust', 'label'),
    oils_i18n_gettext('circ.transit.suppress_non_hold',
        'If set to a non-empty value, Non-Hold Transits will be suppressed between this OU and others with the same value. If set to an empty value, transits will not be suppressed.',
        'coust', 'description'),
    'string');


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0632', :eg_version);

INSERT INTO config.org_unit_setting_type (name, grp, label, description, datatype) VALUES
( 'opac.username_regex', 'glob',
    oils_i18n_gettext('opac.username_regex',
        'Patron username format',
        'coust', 'label'),
    oils_i18n_gettext('opac.username_regex',
        'Regular expression defining the patron username format, used for patron registration and self-service username changing only',
        'coust', 'description'),
    'string')
,( 'opac.lock_usernames', 'glob',
    oils_i18n_gettext('opac.lock_usernames',
        'Lock Usernames',
        'coust', 'label'),
    oils_i18n_gettext('opac.lock_usernames',
        'If enabled username changing via the OPAC will be disabled',
        'coust', 'description'),
    'bool')
,( 'opac.unlimit_usernames', 'glob',
    oils_i18n_gettext('opac.unlimit_usernames',
        'Allow multiple username changes',
        'coust', 'label'),
    oils_i18n_gettext('opac.unlimit_usernames',
        'If enabled (and Lock Usernames is not set) patrons will be allowed to change their username when it does not look like a barcode. Otherwise username changing in the OPAC will only be allowed when the patron''s username looks like a barcode.',
        'coust', 'description'),
    'bool')
;

-- Evergreen DB patch 0635.data.opac.jump-to-details-setting.sql
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0635', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype )
    VALUES (
        'opac.staff.jump_to_details_on_single_hit', 
        'opac',
        oils_i18n_gettext(
            'opac.staff.jump_to_details_on_single_hit',
            'Jump to details on 1 hit (staff client)',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.staff.jump_to_details_on_single_hit',
            'When a search yields only 1 result, jump directly to the record details page.  This setting only affects the OPAC within the staff client',
            'coust', 
            'description'
        ),
        'bool'
    ), (
        'opac.patron.jump_to_details_on_single_hit', 
        'opac',
        oils_i18n_gettext(
            'opac.patron.jump_to_details_on_single_hit',
            'Jump to details on 1 hit (public)',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.patron.jump_to_details_on_single_hit',
            'When a search yields only 1 result, jump directly to the record details page.  This setting only affects the public OPAC',
            'coust', 
            'description'
        ),
        'bool'
    );

-- Evergreen DB patch 0636.data.grace_period_extend.sql
--
-- OU setting turns on grace period auto extension. By default they only do so
-- when the grace period ends on a closed date, but there are two modifiers to
-- change that.
-- 
-- The first modifier causes grace periods to extend for all closed dates that
-- they intersect. This is "grace periods are only consumed by open days."
-- 
-- The second modifier causes a grace period that ends just before a closed
-- day, with or without extension having happened, to include the closed day
-- (and any following it) as well. This is mainly so that a backdate into the
-- closed period following the grace period will assume the "best case" of the
-- item having been returned after hours on the last day of the closed date.
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0636', :eg_version);

INSERT INTO config.org_unit_setting_type(name, grp, label, description, datatype) VALUES

( 'circ.grace.extend', 'circ',
    oils_i18n_gettext('circ.grace.extend',
        'Auto-Extend Grace Periods',
        'coust', 'label'),
    oils_i18n_gettext('circ.grace.extend',
        'When enabled grace periods will auto-extend. By default this will be only when they are a full day or more and end on a closed date, though other options can alter this.',
        'coust', 'description'),
    'bool')

,( 'circ.grace.extend.all', 'circ',
    oils_i18n_gettext('circ.grace.extend.all',
        'Auto-Extending Grace Periods extend for all closed dates',
        'coust', 'label'),
    oils_i18n_gettext('circ.grace.extend.all',
        'If enabled and Grace Periods auto-extending is turned on grace periods will extend past all closed dates they intersect, within hard-coded limits. This basically becomes "grace periods can only be consumed by closed dates".',
        'coust', 'description'),
    'bool')

,( 'circ.grace.extend.into_closed', 'circ',
    oils_i18n_gettext('circ.grace.extend.into_closed',
        'Auto-Extending Grace Periods include trailing closed dates',
        'coust', 'label'),
    oils_i18n_gettext('circ.grace.extend.into_closed',
         'If enabled and Grace Periods auto-extending is turned on grace periods will include closed dates that directly follow the last day of the grace period, to allow a backdate into the closed dates to assume "returned after hours on the last day of the grace period, and thus still within it" automatically.',
        'coust', 'description'),
    'bool');


-- XXXX.schema-acs-nfi.sql

SELECT evergreen.upgrade_deps_block_check('0640', :eg_version);

-- AFTER UPDATE OR INSERT trigger for authority.record_entry
CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
        DELETE FROM authority.simple_heading WHERE record = NEW.id;
          -- Should remove matching $0 from controlled fields at the same time?
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;

        -- Propagate these updates to any linked bib records
        PERFORM authority.propagate_changes(NEW.id) FROM authority.record_entry WHERE id = NEW.id;

        DELETE FROM authority.simple_heading WHERE record = NEW.id;
    END IF;

    INSERT INTO authority.simple_heading (record,atag,value,sort_value)
        SELECT record, atag, value, sort_value FROM authority.simple_heading_set(NEW.marc);

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(NEW.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(NEW.id);
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

-- Entries that need to respect an NFI
UPDATE authority.control_set_authority_field SET nfi = '2'
    WHERE id IN (4,24,44,64);

DROP TRIGGER authority_full_rec_fti_trigger ON authority.full_rec;
CREATE TRIGGER authority_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.full_rec
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

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
    auth_id         INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml)::INT;
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

CREATE OR REPLACE FUNCTION authority.simple_normalize_heading( marcxml TEXT ) RETURNS TEXT AS $func$
    SELECT authority.normalize_heading($1, TRUE);
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION authority.normalize_heading( marcxml TEXT ) RETURNS TEXT AS $func$
    SELECT authority.normalize_heading($1, FALSE);
$func$ LANGUAGE SQL IMMUTABLE;


CREATE TABLE authority.simple_heading (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL REFERENCES authority.record_entry (id),
    atag            INT         NOT NULL REFERENCES authority.control_set_authority_field (id),
    value           TEXT        NOT NULL,
    sort_value      TEXT        NOT NULL,
    index_vector    tsvector    NOT NULL
);
CREATE TRIGGER authority_simple_heading_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.simple_heading
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE INDEX authority_simple_heading_index_vector_idx ON authority.simple_heading USING GIST (index_vector);
CREATE INDEX authority_simple_heading_value_idx ON authority.simple_heading (value);
CREATE INDEX authority_simple_heading_sort_value_idx ON authority.simple_heading (sort_value);

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml)::INT;
BEGIN

    res.record := auth_id;

    SELECT  control_set INTO cset
      FROM  authority.control_set_authority_field
      WHERE tag IN ( SELECT UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]) )
      LIMIT 1;

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP

        res.atag := acsaf.id;
        tag_used := acsaf.tag;
        nfi_used := acsaf.nfi;

        FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)) LOOP
            heading_text := '';

            FOR sf IN SELECT * FROM regexp_split_to_table(acsaf.sf_list,'') LOOP
                heading_text := heading_text || COALESCE( ' ' || oils_xpath_string('//*[@code="'||sf||'"]',tmp_xml::TEXT), '');
            END LOOP;

            heading_text := public.naco_normalize(heading_text);
            
            IF nfi_used IS NOT NULL THEN

                sort_text := SUBSTRING(
                    heading_text FROM
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

            ELSE
                sort_text := heading_text;
            END IF;

            IF heading_text IS NOT NULL AND heading_text <> '' THEN
                res.value := heading_text;
                res.sort_value := sort_text;
                RETURN NEXT res;
            END IF;

        END LOOP;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

-- Support function used to find the pivot for alpha-heading-browse style searching
CREATE OR REPLACE FUNCTION authority.simple_heading_find_pivot( a INT[], q TEXT ) RETURNS TEXT AS $$
DECLARE
    sort_value_row  RECORD;
    value_row       RECORD;
    t_term          TEXT;
BEGIN

    t_term := public.naco_normalize(q);

    SELECT  CASE WHEN ash.sort_value LIKE t_term || '%' THEN 1 ELSE 0 END
                + CASE WHEN ash.value LIKE t_term || '%' THEN 1 ELSE 0 END AS rank,
            ash.sort_value
      INTO  sort_value_row
      FROM  authority.simple_heading ash
      WHERE ash.atag = ANY (a)
            AND ash.sort_value >= t_term
      ORDER BY rank DESC, ash.sort_value
      LIMIT 1;

    SELECT  CASE WHEN ash.sort_value LIKE t_term || '%' THEN 1 ELSE 0 END
                + CASE WHEN ash.value LIKE t_term || '%' THEN 1 ELSE 0 END AS rank,
            ash.sort_value
      INTO  value_row
      FROM  authority.simple_heading ash
      WHERE ash.atag = ANY (a)
            AND ash.value >= t_term
      ORDER BY rank DESC, ash.sort_value
      LIMIT 1;

    IF value_row.rank > sort_value_row.rank THEN
        RETURN value_row.sort_value;
    ELSE
        RETURN sort_value_row.sort_value;
    END IF;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION authority.simple_heading_browse_center( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
DECLARE
    pivot_sort_value    TEXT;
    boffset             INT DEFAULT 0;
    aoffset             INT DEFAULT 0;
    blimit              INT DEFAULT 0;
    alimit              INT DEFAULT 0;
BEGIN

    pivot_sort_value := authority.simple_heading_find_pivot(atag_list,q);

    IF page = 0 THEN
        blimit := pagesize / 2;
        alimit := blimit;

        IF pagesize % 2 <> 0 THEN
            alimit := alimit + 1;
        END IF;
    ELSE
        blimit := pagesize;
        alimit := blimit;

        boffset := pagesize / 2;
        aoffset := boffset;

        IF pagesize % 2 <> 0 THEN
            boffset := boffset + 1;
        END IF;
    END IF;

    IF page <= 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT id FROM (
                SELECT  ash.id,
                        row_number() over ()
                  FROM  authority.simple_heading ash
                  WHERE ash.atag = ANY (atag_list)
                        AND ash.sort_value < pivot_sort_value
                  ORDER BY ash.sort_value DESC
                  LIMIT blimit
                  OFFSET ABS(page) * pagesize - boffset
            ) x ORDER BY row_number DESC;
    END IF;

    IF page >= 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT  ash.id
              FROM  authority.simple_heading ash
              WHERE ash.atag = ANY (atag_list)
                    AND ash.sort_value >= pivot_sort_value
              ORDER BY ash.sort_value
              LIMIT alimit
              OFFSET ABS(page) * pagesize - aoffset;
    END IF;
END;
$$ LANGUAGE PLPGSQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.simple_heading_browse_top( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
DECLARE
    pivot_sort_value    TEXT;
BEGIN

    pivot_sort_value := authority.simple_heading_find_pivot(atag_list,q);

    IF page < 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT id FROM (
                SELECT  ash.id,
                        row_number() over ()
                  FROM  authority.simple_heading ash
                  WHERE ash.atag = ANY (atag_list)
                        AND ash.sort_value < pivot_sort_value
                  ORDER BY ash.sort_value DESC
                  LIMIT pagesize
                  OFFSET (ABS(page) - 1) * pagesize
            ) x ORDER BY row_number DESC;
    END IF;

    IF page >= 0 THEN
        RETURN QUERY
            -- "bottom" half of the browse results
            SELECT  ash.id
              FROM  authority.simple_heading ash
              WHERE ash.atag = ANY (atag_list)
                    AND ash.sort_value >= pivot_sort_value
              ORDER BY ash.sort_value
              LIMIT pagesize
              OFFSET ABS(page) * pagesize ;
    END IF;
END;
$$ LANGUAGE PLPGSQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.simple_heading_search_rank( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT  ash.id
      FROM  authority.simple_heading ash,
            public.naco_normalize($2) t(term),
            plainto_tsquery('keyword'::regconfig,$2) ptsq(term)
      WHERE ash.atag = ANY ($1)
            AND ash.index_vector @@ ptsq.term
      ORDER BY ts_rank_cd(ash.index_vector,ptsq.term,14)::numeric
                    + CASE WHEN ash.sort_value LIKE t.term || '%' THEN 2 ELSE 0 END
                    + CASE WHEN ash.value LIKE t.term || '%' THEN 1 ELSE 0 END DESC
      LIMIT $4
      OFFSET $4 * $3;
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.simple_heading_search_heading( atag_list INT[], q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT  ash.id
      FROM  authority.simple_heading ash,
            public.naco_normalize($2) t(term),
            plainto_tsquery('keyword'::regconfig,$2) ptsq(term)
      WHERE ash.atag = ANY ($1)
            AND ash.index_vector @@ ptsq.term
      ORDER BY ash.sort_value
      LIMIT $4
      OFFSET $4 * $3;
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.axis_authority_tags(a TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_ACCUM(field) FROM authority.browse_axis_authority_field_map WHERE axis = $1;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.axis_authority_tags_refs(a TEXT) RETURNS INT[] AS $$
    SELECT  ARRAY_CAT(
                ARRAY[a.field],
                (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.field)
            )
      FROM  authority.browse_axis_authority_field_map a
      WHERE axis = $1
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION authority.btag_authority_tags(btag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_ACCUM(authority_field) FROM authority.control_set_bib_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.btag_authority_tags_refs(btag TEXT) RETURNS INT[] AS $$
    SELECT  ARRAY_CAT(
                ARRAY[a.authority_field],
                (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.authority_field)
            )
      FROM  authority.control_set_bib_field a
      WHERE a.tag = $1
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION authority.atag_authority_tags(atag TEXT) RETURNS INT[] AS $$
    SELECT ARRAY_ACCUM(id) FROM authority.control_set_authority_field WHERE tag = $1
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.atag_authority_tags_refs(atag TEXT) RETURNS INT[] AS $$
    SELECT  ARRAY_CAT(
                ARRAY[a.id],
                (SELECT ARRAY_ACCUM(x.id) FROM authority.control_set_authority_field x WHERE x.main_entry = a.id)
            )
      FROM  authority.control_set_authority_field a
      WHERE a.tag = $1
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION authority.axis_browse_center( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.axis_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_center( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.btag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_center( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.atag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_browse_center_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.axis_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_center_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.btag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_center_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 9 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_center(authority.atag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.axis_browse_top( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.axis_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_top( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.btag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_top( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.atag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_browse_top_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.axis_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_browse_top_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.btag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_browse_top_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_browse_top(authority.atag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.axis_search_rank( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.axis_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_rank( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.btag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_rank( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.atag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_search_rank_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.axis_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_rank_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.btag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_rank_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_rank(authority.atag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;


CREATE OR REPLACE FUNCTION authority.axis_search_heading( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.axis_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_heading( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.btag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_heading( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.atag_authority_tags($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.axis_search_heading_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.axis_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.btag_search_heading_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.btag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION authority.atag_search_heading_refs( a TEXT, q TEXT, page INT DEFAULT 0, pagesize INT DEFAULT 10 ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM authority.simple_heading_search_heading(authority.atag_authority_tags_refs($1), $2, $3, $4)
$$ LANGUAGE SQL ROWS 10;



-- Evergreen DB patch 0641.schema.org_unit_setting_json_check.sql
--
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0641', :eg_version);

ALTER TABLE actor.org_unit_setting ADD CONSTRAINT aous_must_be_json CHECK ( is_json(value) );

-- Evergreen DB patch 0642.data.acq-worksheet-hold-count.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0642', :eg_version);

UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%- SET li = target; -%]
<div class="wrapper">
    <div class="summary" style='font-size:110%; font-weight:bold;'>

        <div>Title: [% helpers.get_li_attr("title", "", li.attributes) %]</div>
        <div>Author: [% helpers.get_li_attr("author", "", li.attributes) %]</div>
        <div class="count">Item Count: [% li.lineitem_details.size %]</div>
        <div class="lineid">Lineitem ID: [% li.id %]</div>
        <div>Open Holds: [% helpers.bre_open_hold_count(li.eg_bib_id) %]</div>

        [% IF li.distribution_formulas.size > 0 %]
            [% SET forms = [] %]
            [% FOREACH form IN li.distribution_formulas; forms.push(form.formula.name); END %]
            <div>Distribution Formulas: [% forms.join(',') %]</div>
        [% END %]

        [% IF li.lineitem_notes.size > 0 %]
            Lineitem Notes:
            <ul>
                [%- FOR note IN li.lineitem_notes -%]
                    <li>
                    [% IF note.alert_text %]
                        [% note.alert_text.code -%] 
                        [% IF note.value -%]
                            : [% note.value %]
                        [% END %]
                    [% ELSE %]
                        [% note.value -%] 
                    [% END %]
                    </li>
                [% END %]
            </ul>
        [% END %]
    </div>
    <br/>
    <table>
        <thead>
            <tr>
                <th>Branch</th>
                <th>Barcode</th>
                <th>Call Number</th>
                <th>Fund</th>
                <th>Shelving Location</th>
                <th>Recd.</th>
                <th>Notes</th>
            </tr>
        </thead>
        <tbody>
        [% FOREACH detail IN li.lineitem_details.sort('owning_lib') %]
            [% 
                IF detail.eg_copy_id;
                    SET copy = detail.eg_copy_id;
                    SET cn_label = copy.call_number.label;
                ELSE; 
                    SET copy = detail; 
                    SET cn_label = detail.cn_label;
                END 
            %]
            <tr>
                <!-- acq.lineitem_detail.id = [%- detail.id -%] -->
                <td style='padding:5px;'>[% detail.owning_lib.shortname %]</td>
                <td style='padding:5px;'>[% IF copy.barcode   %]<span class="barcode"  >[% detail.barcode   %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF cn_label %]<span class="cn_label" >[% cn_label  %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF detail.fund %]<span class="fund">[% detail.fund.code %] ([% detail.fund.year %])</span>[% END %]</td>
                <td style='padding:5px;'>[% copy.location.name %]</td>
                <td style='padding:5px;'>[% IF detail.recv_time %]<span class="recv_time">[% detail.recv_time %]</span>[% END %]</td>
                <td style='padding:5px;'>[% detail.note %]</td>
            </tr>
        [% END %]
        </tbody>
    </table>
</div>
$$
WHERE id = 14;


SELECT evergreen.upgrade_deps_block_check('0643', :eg_version);

DO $$
DECLARE x TEXT;
BEGIN

    FOR x IN
        SELECT  marc
          FROM  authority.record_entry
          WHERE id > 0
                AND NOT deleted
                AND id NOT IN (SELECT DISTINCT record FROM authority.simple_heading)
    LOOP
        INSERT INTO authority.simple_heading (record,atag,value,sort_value)
            SELECT record, atag, value, sort_value FROM authority.simple_heading_set(x);
    END LOOP;
END;
$$;



SELECT evergreen.upgrade_deps_block_check('0644', :eg_version);

INSERT into config.org_unit_setting_type (name, grp, label, description, datatype) VALUES
( 'circ.holds.target_when_closed', 'circ',
    oils_i18n_gettext('circ.holds.target_when_closed',
        'Target copies for a hold even if copy''s circ lib is closed',
        'coust', 'label'),
    oils_i18n_gettext('circ.holds.target_when_closed',
        'If this setting is true at a given org unit or one of its ancestors, the hold targeter will target copies from this org unit even if the org unit is closed (according to the actor.org_unit.closed_date table).',
        'coust', 'description'),
    'bool'),
( 'circ.holds.target_when_closed_if_at_pickup_lib', 'circ',
    oils_i18n_gettext('circ.holds.target_when_closed_if_at_pickup_lib',
        'Target copies for a hold even if copy''s circ lib is closed IF the circ lib is the hold''s pickup lib',
        'coust', 'label'),
    oils_i18n_gettext('circ.holds.target_when_closed_if_at_pickup_lib',
        'If this setting is true at a given org unit or one of its ancestors, the hold targeter will target copies from this org unit even if the org unit is closed (according to the actor.org_unit.closed_date table) IF AND ONLY IF the copy''s circ lib is the same as the hold''s pickup lib.',
        'coust', 'description'),
    'bool')
;

-- Evergreen DB patch XXXX.data.hold-notification-cleanup-mod.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0647', :eg_version);

INSERT INTO action_trigger.cleanup ( module, description ) VALUES (
    'CreateHoldNotification',
    oils_i18n_gettext(
        'CreateHoldNotification',
        'Creates a hold_notification record for each notified hold',
        'atclean',
        'description'
    )
);

UPDATE action_trigger.event_definition 
    SET 
        cleanup_success = 'CreateHoldNotification' 
    WHERE 
        id = 5 -- stock hold-ready email event_def
        AND cleanup_success IS NULL; -- don't clobber any existing cleanup mod

-- Evergreen DB patch XXXX.schema.unnest-hold-permit-upgrade-script-repair.sql
--
-- This patch makes no changes to the baseline schema and is 
-- only meant to repair a previous upgrade script.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0651', :eg_version);

--Removed dupe action.hold_request_permit_test

-- Evergreen DB patch XXXX.data.vandelay-queue-bib-bucket-type.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0652', :eg_version);

INSERT INTO container.biblio_record_entry_bucket_type (code, label) VALUES (
    'vandelay_queue',
    oils_i18n_gettext('vandelay_queue', 'Vandelay Queue', 'cbrebt', 'label')
);

-- Evergreen DB patch XXXX.schema.unapi-indb-optional-org.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0653', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.org_top() RETURNS SETOF actor.org_unit AS $$ SELECT * FROM actor.org_unit WHERE parent_ou IS NULL LIMIT 1; $$ LANGUAGE SQL ROWS 1;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT DEFAULT '-', depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

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

CREATE OR REPLACE FUNCTION unapi.bre ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT DEFAULT '-', depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

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




SELECT evergreen.upgrade_deps_block_check('0654', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 514, 'UPDATE_PATRON_ACTIVE_CARD', oils_i18n_gettext( 514,
    'Allows a user to manually adjust a patron''s active cards', 'ppl', 'description')),
 ( 515, 'UPDATE_PATRON_PRIMARY_CARD', oils_i18n_gettext( 515,
    'Allows a user to manually adjust a patron''s primary card', 'ppl', 'description'));

-- Evergreen DB patch 0655.config.bib_source.can_have_copies.sql
--
-- This column introduces the ability to prevent bib records associated
-- with specific bib sources from being able to have volumes or MFHD
-- records attached to them.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0655', :eg_version);

ALTER TABLE config.bib_source
ADD COLUMN can_have_copies BOOL NOT NULL DEFAULT TRUE;

-- Evergreen DB patch XXXX.LP893315_schema.function.filter_deleted_acns_from_unapi.holdings_xml.sql
--
-- Prevent deleted call numbers from hiding active call numbers / copies / URIs
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0656', :eg_version);

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ($5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
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
                        XMLELEMENT(
                            name monograph_parts,
                            (SELECT XMLAGG(bmp) FROM (
                                SELECT  unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE)
                                  FROM  biblio.monograph_part
                                  WHERE record = $1
                            )x)
                        )
                     ELSE NULL
                 END,
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn) FROM (
                        SELECT  unapi.acn(acn.id,'xml','volume',array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE)
                          FROM  asset.call_number acn
                          WHERE acn.record = $1
                                AND acn.deleted IS FALSE
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
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN 
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

-- Evergreen DB patch 0657.schema.address-alert.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0657', :eg_version);

CREATE TABLE actor.address_alert (
    id              SERIAL  PRIMARY KEY,
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    active          BOOL    NOT NULL DEFAULT TRUE,
    match_all       BOOL    NOT NULL DEFAULT TRUE,
    alert_message   TEXT    NOT NULL,
    street1         TEXT,
    street2         TEXT,
    city            TEXT,
    county          TEXT,
    state           TEXT,
    country         TEXT,
    post_code       TEXT,
    mailing_address BOOL    NOT NULL DEFAULT FALSE,
    billing_address BOOL    NOT NULL DEFAULT FALSE
);

CREATE OR REPLACE FUNCTION actor.address_alert_matches (
        org_unit INT, 
        street1 TEXT, 
        street2 TEXT, 
        city TEXT, 
        county TEXT, 
        state TEXT, 
        country TEXT, 
        post_code TEXT,
        mailing_address BOOL DEFAULT FALSE,
        billing_address BOOL DEFAULT FALSE
    ) RETURNS SETOF actor.address_alert AS $$

SELECT *
FROM actor.address_alert
WHERE
    active
    AND owner IN (SELECT id FROM actor.org_unit_ancestors($1)) 
    AND (
        (NOT mailing_address AND NOT billing_address)
        OR (mailing_address AND $9)
        OR (billing_address AND $10)
    )
    AND (
            (
                match_all
                AND COALESCE($2, '') ~* COALESCE(street1,   '.*')
                AND COALESCE($3, '') ~* COALESCE(street2,   '.*')
                AND COALESCE($4, '') ~* COALESCE(city,      '.*')
                AND COALESCE($5, '') ~* COALESCE(county,    '.*')
                AND COALESCE($6, '') ~* COALESCE(state,     '.*')
                AND COALESCE($7, '') ~* COALESCE(country,   '.*')
                AND COALESCE($8, '') ~* COALESCE(post_code, '.*')
            ) OR (
                NOT match_all 
                AND (  
                       $2 ~* street1
                    OR $3 ~* street2
                    OR $4 ~* city
                    OR $5 ~* county
                    OR $6 ~* state
                    OR $7 ~* country
                    OR $8 ~* post_code
                )
            )
        )
    ORDER BY actor.org_unit_proximity(owner, $1)
$$ LANGUAGE SQL;


/* UNDO
DROP FUNCTION actor.address_alert_matches(INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOL, BOOL);
DROP TABLE actor.address_alert;
*/
-- Evergreen DB patch 0659.add_create_report_perms.sql
--
-- Add a permission to control the ability to create report templates
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0659', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 516, 'CREATE_REPORT_TEMPLATE', oils_i18n_gettext( 516,
    'Allows a user to create report templates', 'ppl', 'description' ));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, 516, depth, grantable
        FROM permission.grp_perm_map
        WHERE perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'RUN_REPORTS'
        );



SELECT evergreen.upgrade_deps_block_check('0660', :eg_version);

UPDATE action_trigger.event_definition SET template = $$
[%-
# target is the bookbag itself. The 'items' variable does not need to be in
# the environment because a special reactor will take care of filling it in.

FOR item IN items;
    bibxml = helpers.unapi_bre(item.target_biblio_record_entry, {flesh => '{mra}'});
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');

    helpers.csv_datum(title) %],[% helpers.csv_datum(author) %],[% helpers.csv_datum(item_type) %],[% FOR note IN item.notes; helpers.csv_datum(note.note); ","; END; "\n";
END -%]
$$
WHERE reactor = 'ContainerCSV';

-- Evergreen DB patch 0661.data.yaous-opac-tag-circed-items.sql
--
-- Add org unit setting that enables users who have opted in to
-- tracking their circulation history to see which items they
-- have previously checked out in search results.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0661', :eg_version);

INSERT into config.org_unit_setting_type 
    (name, grp, label, description, datatype) 
    VALUES ( 
        'opac.search.tag_circulated_items', 
        'opac',
        oils_i18n_gettext(
            'opac.search.tag_circulated_items',
            'Tag Circulated Items in Results',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.search.tag_circulated_items',
            'When a user is both logged in and has opted in to circulation history tracking, turning on this setting will cause previous (or currently) circulated items to be highlighted in search results',
            'coust', 
            'description'
        ),
        'bool'
    );


-- Evergreen DB patch 0662.schema.coded-value-map-index-normalizer.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0662', :eg_version);

-- create the normalizer
CREATE OR REPLACE FUNCTION evergreen.coded_value_map_normalizer( input TEXT, ctype TEXT ) 
    RETURNS TEXT AS $F$
        SELECT COALESCE(value,$1) 
            FROM config.coded_value_map 
            WHERE ctype = $2 AND code = $1;
$F$ LANGUAGE SQL;

-- register the normalizer
INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
    'Coded Value Map Normalizer', 
    'Applies coded_value_map mapping of values',
    'coded_value_map_normalizer', 
    1
);

-- Evergreen DB patch 0663.schema.archive_circ_stat_cats.sql
--
-- Enables users to set copy and patron stat cats to be archivable
-- for the purposes of statistics even after the circs are aged.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0663', :eg_version);

-- New tables

CREATE TABLE action.archive_actor_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL,
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

CREATE TABLE action.archive_asset_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL,
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

-- Add columns to existing tables

-- Archive Flag Columns
ALTER TABLE actor.stat_cat
    ADD COLUMN checkout_archive BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE asset.stat_cat
    ADD COLUMN checkout_archive BOOL NOT NULL DEFAULT FALSE;

-- Circulation copy column
ALTER TABLE action.circulation
    ADD COLUMN copy_location INT NULL REFERENCES asset.copy_location(id) DEFERRABLE INITIALLY DEFERRED;

-- Create trigger function to auto-fill the copy_location field
CREATE OR REPLACE FUNCTION action.fill_circ_copy_location () RETURNS TRIGGER AS $$
BEGIN
    SELECT INTO NEW.copy_location location FROM asset.copy WHERE id = NEW.target_copy;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Create trigger function to auto-archive stat cat entries
CREATE OR REPLACE FUNCTION action.archive_stat_cats () RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO action.archive_actor_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, asceum.stat_cat, asceum.stat_cat_entry
        FROM actor.stat_cat_entry_usr_map asceum
             JOIN actor.stat_cat sc ON asceum.stat_cat = sc.id
        WHERE NEW.usr = asceum.target_usr AND sc.checkout_archive;
    INSERT INTO action.archive_asset_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, ascecm.stat_cat, asce.value
        FROM asset.stat_cat_entry_copy_map ascecm
             JOIN asset.stat_cat sc ON ascecm.stat_cat = sc.id
             JOIN asset.stat_cat_entry asce ON ascecm.stat_cat_entry = asce.id
        WHERE NEW.target_copy = ascecm.owning_copy AND sc.checkout_archive;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

-- Apply triggers
CREATE TRIGGER fill_circ_copy_location_tgr BEFORE INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.fill_circ_copy_location();
CREATE TRIGGER archive_stat_cats_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.archive_stat_cats();

-- Ensure all triggers are disabled for speedy updates!
ALTER TABLE action.circulation DISABLE TRIGGER ALL;

-- Update view to use circ's copy_location field instead of the copy's current copy_location field
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
        cp.call_number AS copy_call_number, circ.copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
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
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);

-- Update action.circulation with real copy_location numbers instead of all NULL
DO $$BEGIN RAISE WARNING 'We are about to do an update on every row in action.circulation. This may take a while. %', timeofday(); END;$$;
UPDATE action.circulation circ SET copy_location = ac.location FROM asset.copy ac WHERE ac.id = circ.target_copy;

-- Set not null/default on new column, re-enable triggers
ALTER TABLE action.circulation
    ALTER COLUMN copy_location SET NOT NULL,
    ALTER COLUMN copy_location SET DEFAULT 1,
    ENABLE TRIGGER ALL;

-- Evergreen DB patch 0664.schema.hold-current-shelf-lib.sql
--
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0664', :eg_version);

-- add the new column
ALTER TABLE action.hold_request ADD COLUMN current_shelf_lib 
    INT REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED;

-- Add some others before the UPDATE we are about to do breaks our ability to add columns
-- But we need this table first.
CREATE TABLE config.sms_carrier (
    id              SERIAL PRIMARY KEY,
    region          TEXT,
    name            TEXT,
    email_gateway   TEXT,
    active          BOOLEAN DEFAULT TRUE
);

ALTER TABLE action.hold_request ADD COLUMN sms_notify TEXT;
ALTER TABLE action.hold_request ADD COLUMN sms_carrier INT REFERENCES config.sms_carrier (id);
ALTER TABLE action.hold_request ADD CONSTRAINT sms_check CHECK (
    sms_notify IS NULL
    OR sms_carrier IS NOT NULL -- and implied sms_notify IS NOT NULL
);



-- set the value for current_shelf_lib on existing shelved holds
UPDATE action.hold_request
    SET current_shelf_lib = pickup_lib
    FROM asset.copy
    WHERE 
            action.hold_request.shelf_time IS NOT NULL 
        AND action.hold_request.capture_time IS NOT NULL
        AND action.hold_request.current_copy IS NOT NULL
        AND action.hold_request.fulfillment_time IS NULL
        AND action.hold_request.cancel_time IS NULL
        AND asset.copy.id = action.hold_request.current_copy
        AND asset.copy.status = 8; -- on holds shelf


SELECT evergreen.upgrade_deps_block_check('0666', :eg_version);

-- 950.data.seed-values.sql
INSERT INTO config.settings_group (name, label) VALUES
    (
        'sms',
        oils_i18n_gettext(
            'sms',
            'SMS Text Messages',
            'csg',
            'label'
        )
    )
;

INSERT INTO config.org_unit_setting_type (name, grp, label, description, datatype) VALUES
    (
        'sms.enable',
        'sms',
        oils_i18n_gettext(
            'sms.enable',
            'Enable features that send SMS text messages.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'sms.enable',
            'Current features that use SMS include hold-ready-for-pickup notifications and a "Send Text" action for call numbers in the OPAC. If this setting is not enabled, the SMS options will not be offered to the user.  Unless you are carefully silo-ing patrons and their use of the OPAC, the context org for this setting should be the top org in the org hierarchy, otherwise patrons can trample their user settings when jumping between orgs.',
            'coust',
            'description'
        ),
        'bool'
    )
    ,(
        'sms.disable_authentication_requirement.callnumbers',
        'sms',
        oils_i18n_gettext(
            'sms.disable_authentication_requirement.callnumbers',
            'Disable auth requirement for texting call numbers.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'sms.disable_authentication_requirement.callnumbers',
            'Disable authentication requirement for sending call number information via SMS from the OPAC.',
            'coust',
            'description'
        ),
        'bool'
    )
;

-- 090.schema.action.sql
-- 950.data.seed-values.sql
INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype,fm_class) VALUES (
    'opac.default_sms_carrier',
    'sms',
    TRUE,
    oils_i18n_gettext(
        'opac.default_sms_carrier',
        'Default SMS/Text Carrier',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_sms_carrier',
        'Default SMS/Text Carrier',
        'cust',
        'description'
    ),
    'link',
    'csc'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'opac.default_sms_notify',
    'sms',
    TRUE,
    oils_i18n_gettext(
        'opac.default_sms_notify',
        'Default SMS/Text Number',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_sms_notify',
        'Default SMS/Text Number',
        'cust',
        'description'
    ),
    'string'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'opac.default_phone',
    'opac',
    TRUE,
    oils_i18n_gettext(
        'opac.default_phone',
        'Default Phone Number',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_phone',
        'Default Phone Number',
        'cust',
        'description'
    ),
    'string'
);

SELECT setval( 'config.sms_carrier_id_seq', 1000 );
INSERT INTO config.sms_carrier VALUES

    -- Testing
    (
        1,
        oils_i18n_gettext(
            1,
            'Local',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            1,
            'Test Carrier',
            'csc',
            'name'
        ),
        'opensrf+$number@localhost',
        FALSE
    ),

    -- Canada & USA
    (
        2,
        oils_i18n_gettext(
            2,
            'Canada & USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            2,
            'Rogers Wireless',
            'csc',
            'name'
        ),
        '$number@pcs.rogers.com',
        TRUE
    ),
    (
        3,
        oils_i18n_gettext(
            3,
            'Canada & USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            3,
            'Rogers Wireless (Alternate)',
            'csc',
            'name'
        ),
        '1$number@mms.rogers.com',
        TRUE
    ),
    (
        4,
        oils_i18n_gettext(
            4,
            'Canada & USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            4,
            'Telus Mobility',
            'csc',
            'name'
        ),
        '$number@msg.telus.com',
        TRUE
    ),

    -- Canada
    (
        5,
        oils_i18n_gettext(
            5,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            5,
            'Koodo Mobile',
            'csc',
            'name'
        ),
        '$number@msg.telus.com',
        TRUE
    ),
    (
        6,
        oils_i18n_gettext(
            6,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            6,
            'Fido',
            'csc',
            'name'
        ),
        '$number@fido.ca',
        TRUE
    ),
    (
        7,
        oils_i18n_gettext(
            7,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            7,
            'Bell Mobility & Solo Mobile',
            'csc',
            'name'
        ),
        '$number@txt.bell.ca',
        TRUE
    ),
    (
        8,
        oils_i18n_gettext(
            8,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            8,
            'Bell Mobility & Solo Mobile (Alternate)',
            'csc',
            'name'
        ),
        '$number@txt.bellmobility.ca',
        TRUE
    ),
    (
        9,
        oils_i18n_gettext(
            9,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            9,
            'Aliant',
            'csc',
            'name'
        ),
        '$number@sms.wirefree.informe.ca',
        TRUE
    ),
    (
        10,
        oils_i18n_gettext(
            10,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            10,
            'PC Telecom',
            'csc',
            'name'
        ),
        '$number@mobiletxt.ca',
        TRUE
    ),
    (
        11,
        oils_i18n_gettext(
            11,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            11,
            'SaskTel',
            'csc',
            'name'
        ),
        '$number@sms.sasktel.com',
        TRUE
    ),
    (
        12,
        oils_i18n_gettext(
            12,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            12,
            'MTS Mobility',
            'csc',
            'name'
        ),
        '$number@text.mtsmobility.com',
        TRUE
    ),
    (
        13,
        oils_i18n_gettext(
            13,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            13,
            'Virgin Mobile',
            'csc',
            'name'
        ),
        '$number@vmobile.ca',
        TRUE
    ),

    -- International
    (
        14,
        oils_i18n_gettext(
            14,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            14,
            'Iridium',
            'csc',
            'name'
        ),
        '$number@msg.iridium.com',
        TRUE
    ),
    (
        15,
        oils_i18n_gettext(
            15,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            15,
            'Globalstar',
            'csc',
            'name'
        ),
        '$number@msg.globalstarusa.com',
        TRUE
    ),
    (
        16,
        oils_i18n_gettext(
            16,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            16,
            'Bulletin.net',
            'csc',
            'name'
        ),
        '$number@bulletinmessenger.net', -- International Formatted number
        TRUE
    ),
    (
        17,
        oils_i18n_gettext(
            17,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            17,
            'Panacea Mobile',
            'csc',
            'name'
        ),
        '$number@api.panaceamobile.com',
        TRUE
    ),

    -- USA
    (
        18,
        oils_i18n_gettext(
            18,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            18,
            'C Beyond',
            'csc',
            'name'
        ),
        '$number@cbeyond.sprintpcs.com',
        TRUE
    ),
    (
        19,
        oils_i18n_gettext(
            19,
            'Alaska, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            19,
            'General Communications, Inc.',
            'csc',
            'name'
        ),
        '$number@mobile.gci.net',
        TRUE
    ),
    (
        20,
        oils_i18n_gettext(
            20,
            'California, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            20,
            'Golden State Cellular',
            'csc',
            'name'
        ),
        '$number@gscsms.com',
        TRUE
    ),
    (
        21,
        oils_i18n_gettext(
            21,
            'Cincinnati, Ohio, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            21,
            'Cincinnati Bell',
            'csc',
            'name'
        ),
        '$number@gocbw.com',
        TRUE
    ),
    (
        22,
        oils_i18n_gettext(
            22,
            'Hawaii, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            22,
            'Hawaiian Telcom Wireless',
            'csc',
            'name'
        ),
        '$number@hawaii.sprintpcs.com',
        TRUE
    ),
    (
        23,
        oils_i18n_gettext(
            23,
            'Midwest, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            23,
            'i wireless (T-Mobile)',
            'csc',
            'name'
        ),
        '$number.iws@iwspcs.net',
        TRUE
    ),
    (
        24,
        oils_i18n_gettext(
            24,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            24,
            'i-wireless (Sprint PCS)',
            'csc',
            'name'
        ),
        '$number@iwirelesshometext.com',
        TRUE
    ),
    (
        25,
        oils_i18n_gettext(
            25,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            25,
            'MetroPCS',
            'csc',
            'name'
        ),
        '$number@mymetropcs.com',
        TRUE
    ),
    (
        26,
        oils_i18n_gettext(
            26,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            26,
            'Kajeet',
            'csc',
            'name'
        ),
        '$number@mobile.kajeet.net',
        TRUE
    ),
    (
        27,
        oils_i18n_gettext(
            27,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            27,
            'Element Mobile',
            'csc',
            'name'
        ),
        '$number@SMS.elementmobile.net',
        TRUE
    ),
    (
        28,
        oils_i18n_gettext(
            28,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            28,
            'Esendex',
            'csc',
            'name'
        ),
        '$number@echoemail.net',
        TRUE
    ),
    (
        29,
        oils_i18n_gettext(
            29,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            29,
            'Boost Mobile',
            'csc',
            'name'
        ),
        '$number@myboostmobile.com',
        TRUE
    ),
    (
        30,
        oils_i18n_gettext(
            30,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            30,
            'BellSouth',
            'csc',
            'name'
        ),
        '$number@bellsouth.com',
        TRUE
    ),
    (
        31,
        oils_i18n_gettext(
            31,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            31,
            'Bluegrass Cellular',
            'csc',
            'name'
        ),
        '$number@sms.bluecell.com',
        TRUE
    ),
    (
        32,
        oils_i18n_gettext(
            32,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            32,
            'AT&T Enterprise Paging',
            'csc',
            'name'
        ),
        '$number@page.att.net',
        TRUE
    ),
    (
        33,
        oils_i18n_gettext(
            33,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            33,
            'AT&T Mobility/Wireless',
            'csc',
            'name'
        ),
        '$number@txt.att.net',
        TRUE
    ),
    (
        34,
        oils_i18n_gettext(
            34,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            34,
            'AT&T Global Smart Messaging Suite',
            'csc',
            'name'
        ),
        '$number@sms.smartmessagingsuite.com',
        TRUE
    ),
    (
        35,
        oils_i18n_gettext(
            35,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            35,
            'Alltel (Allied Wireless)',
            'csc',
            'name'
        ),
        '$number@sms.alltelwireless.com',
        TRUE
    ),
    (
        36,
        oils_i18n_gettext(
            36,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            36,
            'Alaska Communications',
            'csc',
            'name'
        ),
        '$number@msg.acsalaska.com',
        TRUE
    ),
    (
        37,
        oils_i18n_gettext(
            37,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            37,
            'Ameritech',
            'csc',
            'name'
        ),
        '$number@paging.acswireless.com',
        TRUE
    ),
    (
        38,
        oils_i18n_gettext(
            38,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            38,
            'Cingular (GoPhone prepaid)',
            'csc',
            'name'
        ),
        '$number@cingulartext.com',
        TRUE
    ),
    (
        39,
        oils_i18n_gettext(
            39,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            39,
            'Cingular (Postpaid)',
            'csc',
            'name'
        ),
        '$number@cingular.com',
        TRUE
    ),
    (
        40,
        oils_i18n_gettext(
            40,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            40,
            'Cellular One (Dobson) / O2 / Orange',
            'csc',
            'name'
        ),
        '$number@mobile.celloneusa.com',
        TRUE
    ),
    (
        41,
        oils_i18n_gettext(
            41,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            41,
            'Cellular South',
            'csc',
            'name'
        ),
        '$number@csouth1.com',
        TRUE
    ),
    (
        42,
        oils_i18n_gettext(
            42,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            42,
            'Cellcom',
            'csc',
            'name'
        ),
        '$number@cellcom.quiktxt.com',
        TRUE
    ),
    (
        43,
        oils_i18n_gettext(
            43,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            43,
            'Chariton Valley Wireless',
            'csc',
            'name'
        ),
        '$number@sms.cvalley.net',
        TRUE
    ),
    (
        44,
        oils_i18n_gettext(
            44,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            44,
            'Cricket',
            'csc',
            'name'
        ),
        '$number@sms.mycricket.com',
        TRUE
    ),
    (
        45,
        oils_i18n_gettext(
            45,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            45,
            'Cleartalk Wireless',
            'csc',
            'name'
        ),
        '$number@sms.cleartalk.us',
        TRUE
    ),
    (
        46,
        oils_i18n_gettext(
            46,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            46,
            'Edge Wireless',
            'csc',
            'name'
        ),
        '$number@sms.edgewireless.com',
        TRUE
    ),
    (
        47,
        oils_i18n_gettext(
            47,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            47,
            'Syringa Wireless',
            'csc',
            'name'
        ),
        '$number@rinasms.com',
        TRUE
    ),
    (
        48,
        oils_i18n_gettext(
            48,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            48,
            'T-Mobile',
            'csc',
            'name'
        ),
        '$number@tmomail.net',
        TRUE
    ),
    (
        49,
        oils_i18n_gettext(
            49,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            49,
            'Straight Talk / PagePlus Cellular',
            'csc',
            'name'
        ),
        '$number@vtext.com',
        TRUE
    ),
    (
        50,
        oils_i18n_gettext(
            50,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            50,
            'South Central Communications',
            'csc',
            'name'
        ),
        '$number@rinasms.com',
        TRUE
    ),
    (
        51,
        oils_i18n_gettext(
            51,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            51,
            'Simple Mobile',
            'csc',
            'name'
        ),
        '$number@smtext.com',
        TRUE
    ),
    (
        52,
        oils_i18n_gettext(
            52,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            52,
            'Sprint (PCS)',
            'csc',
            'name'
        ),
        '$number@messaging.sprintpcs.com',
        TRUE
    ),
    (
        53,
        oils_i18n_gettext(
            53,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            53,
            'Nextel',
            'csc',
            'name'
        ),
        '$number@messaging.nextel.com',
        TRUE
    ),
    (
        54,
        oils_i18n_gettext(
            54,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            54,
            'Pioneer Cellular',
            'csc',
            'name'
        ),
        '$number@zsend.com', -- nine digit number
        TRUE
    ),
    (
        55,
        oils_i18n_gettext(
            55,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            55,
            'Qwest Wireless',
            'csc',
            'name'
        ),
        '$number@qwestmp.com',
        TRUE
    ),
    (
        56,
        oils_i18n_gettext(
            56,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            56,
            'US Cellular',
            'csc',
            'name'
        ),
        '$number@email.uscc.net',
        TRUE
    ),
    (
        57,
        oils_i18n_gettext(
            57,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            57,
            'Unicel',
            'csc',
            'name'
        ),
        '$number@utext.com',
        TRUE
    ),
    (
        58,
        oils_i18n_gettext(
            58,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            58,
            'Teleflip',
            'csc',
            'name'
        ),
        '$number@teleflip.com',
        TRUE
    ),
    (
        59,
        oils_i18n_gettext(
            59,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            59,
            'Virgin Mobile',
            'csc',
            'name'
        ),
        '$number@vmobl.com',
        TRUE
    ),
    (
        60,
        oils_i18n_gettext(
            60,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            60,
            'Verizon Wireless',
            'csc',
            'name'
        ),
        '$number@vtext.com',
        TRUE
    ),
    (
        61,
        oils_i18n_gettext(
            61,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            61,
            'USA Mobility',
            'csc',
            'name'
        ),
        '$number@usamobility.net',
        TRUE
    ),
    (
        62,
        oils_i18n_gettext(
            62,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            62,
            'Viaero',
            'csc',
            'name'
        ),
        '$number@viaerosms.com',
        TRUE
    ),
    (
        63,
        oils_i18n_gettext(
            63,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            63,
            'TracFone',
            'csc',
            'name'
        ),
        '$number@mmst5.tracfone.com',
        TRUE
    ),
    (
        64,
        oils_i18n_gettext(
            64,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            64,
            'Centennial Wireless',
            'csc',
            'name'
        ),
        '$number@cwemail.com',
        TRUE
    ),

    -- South Korea and USA
    (
        65,
        oils_i18n_gettext(
            65,
            'South Korea and USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            65,
            'Helio',
            'csc',
            'name'
        ),
        '$number@myhelio.com',
        TRUE
    )
;

INSERT INTO permission.perm_list ( id, code, description ) VALUES
    (
        519,
        'ADMIN_SMS_CARRIER',
        oils_i18n_gettext(
            519,
            'Allows a user to add/create/delete SMS Carrier entries.',
            'ppl',
            'description'
        )
    )
;

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, TRUE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Global Administrator' AND
        aout.name = 'Consortium' AND
        perm.code = 'ADMIN_SMS_CARRIER';

INSERT INTO action_trigger.reactor (
    module,
    description
) VALUES (
    'SendSMS',
    'Send an SMS text message based on a user-defined template'
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    cleanup_success,
    delay,
    delay_field,
    group_field,
    template
) VALUES (
    true,
    1, -- admin
    'Hold Ready for Pickup SMS Notification',
    'hold.available',
    'HoldIsAvailable',
    'SendSMS',
    'CreateHoldNotification',
    '00:30:00',
    'shelf_time',
    'sms_notify',
    '[%- USE date -%]
[%- user = target.0.usr -%]
From: [%- params.sender_email || default_sender %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(target.0.sms_carrier,target.0.sms_notify) %]
Subject: [% target.size %] hold(s) ready

[% FOR hold IN target %][%-
  bibxml = helpers.xml_doc( hold.current_copy.call_number.record.marc );
  title = "";
  FOR part IN bibxml.findnodes(''//*[@tag="245"]/*[@code="a"]'');
    title = title _ part.textContent;
  END;
  author = bibxml.findnodes(''//*[@tag="100"]/*[@code="a"]'').textContent;
%][% hold.usr.first_given_name %]:[% title %] @ [% hold.pickup_lib.name %]
[% END %]
'
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'current_copy.call_number.record.simple_record'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib.billing_address'
);

INSERT INTO action_trigger.hook(
    key,
    core_type,
    description,
    passive
) VALUES (
    'acn.format.sms_text',
    'acn',
    oils_i18n_gettext(
        'acn.format.sms_text',
        'A text message has been requested for a call number.',
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
    template
) VALUES (
    true,
    1, -- admin
    'SMS Call Number',
    'acn.format.sms_text',
    'NOOP_True',
    'SendSMS',
    '[%- USE date -%]
From: [%- params.sender_email || default_sender %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(user_data.sms_carrier,user_data.sms_notify) %]
Subject: Call Number

[%-
  bibxml = helpers.xml_doc( target.record.marc );
  title = "";
  FOR part IN bibxml.findnodes(''//*[@tag="245"]/*[@code="a" or @code="b"]'');
    title = title _ part.textContent;
  END;
  author = bibxml.findnodes(''//*[@tag="100"]/*[@code="a"]'').textContent;
%]
Call Number: [% target.label %]
Location: [% helpers.get_most_populous_location( target.id ).name %]
Library: [% target.owning_lib.name %]
[%- IF title %]
Title: [% title %]
[%- END %]
[%- IF author %]
Author: [% author %]
[%- END %]
'
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'record.simple_record'
), (
    currval('action_trigger.event_definition_id_seq'),
    'owning_lib.billing_address'
);


-- DELETE FROM actor.usr_setting WHERE name = 'opac.default_phone' OR name in ( SELECT name FROM config.usr_setting_type WHERE grp = 'sms' ); DELETE FROM config.usr_setting_type WHERE name = 'opac.default_phone' OR grp = 'sms'; DELETE FROM actor.org_unit_setting WHERE name in ( SELECT name FROM config.org_unit_setting_type WHERE grp = 'sms' ); DELETE FROM config.org_unit_setting_type_log WHERE field_name in ( SELECT name FROM config.org_unit_setting_type WHERE grp = 'sms' ); DELETE FROM config.org_unit_setting_type WHERE grp = 'sms'; DELETE FROM config.settings_group WHERE name = 'sms'; DELETE FROM permission.grp_perm_map WHERE perm = 519; DELETE FROM permission.perm_list WHERE id = 519; ALTER TABLE action.hold_request DROP CONSTRAINT sms_check; ALTER TABLE action.hold_request DROP COLUMN sms_notify; ALTER TABLE action.hold_request DROP COLUMN sms_carrier; DROP TABLE config.sms_carrier; DELETE FROM action_trigger.event WHERE event_def = ( SELECT id FROM action_trigger.event_definition WHERE name = 'Hold Ready for Pickup SMS Notification' ); DELETE FROM action_trigger.environment WHERE event_def = ( SELECT id FROM action_trigger.event_definition WHERE name = 'Hold Ready for Pickup SMS Notification' ); DELETE FROM action_trigger.event_definition WHERE name = 'Hold Ready for Pickup SMS Notification'; DELETE FROM action_trigger.event WHERE event_def IN ( SELECT id FROM action_trigger.event_definition WHERE hook = 'acn.format.sms_text' ); DELETE FROM action_trigger.environment WHERE event_def IN ( SELECT id FROM action_trigger.event_definition WHERE hook = 'acn.format.sms_text' ); DELETE FROM action_trigger.event_definition WHERE hook = 'acn.format.sms_text'; DELETE FROM action_trigger.hook WHERE key = 'acn.format.sms_text'; DELETE FROM action_trigger.reactor WHERE module = 'SendSMS'; DELETE FROM config.upgrade_log WHERE version = 'XXXX';


SELECT evergreen.upgrade_deps_block_check('0667', :eg_version);

ALTER TABLE config.standing_penalty ADD staff_alert BOOL NOT NULL DEFAULT FALSE;

-- 20 is ALERT_NOTE
-- for backwards compat, set all blocking penalties to alerts
UPDATE config.standing_penalty SET staff_alert = TRUE 
    WHERE id = 20 OR block_list IS NOT NULL;

-- Evergreen DB patch 0668.schema.fix_indb_hold_permit.sql
--
-- FIXME: insert description of change, if needed
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0668', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object     asset.call_number%ROWTYPE;
    item_status_object  config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( pickup_ou );

    result.success := TRUE;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO item_status_object * FROM config.copy_status WHERE id = item_object.status;
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_object.holdable IS FALSE THEN
        result.fail_part := 'item.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_status_object.holdable IS FALSE THEN
        result.fail_part := 'status.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_location_object.holdable IS FALSE THEN
        result.fail_part := 'location.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;
 
    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE '%HOLD%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP
    
            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_cn_object.owning_lib);
        ELSE
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_object.circ_lib);
        END IF;
        IF use_active_date = 'true' THEN
            age_protect_date := COALESCE(item_object.active_date, NOW());
        ELSE
            age_protect_date := item_object.create_date;
        END IF;
        IF age_protect_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


-- Evergreen DB patch 0669.data.recall_and_force_holds.sql
--
-- FIXME: insert description of change, if needed
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0669', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 517, 'COPY_HOLDS_FORCE', oils_i18n_gettext( 517, 
    'Allow a user to place a force hold on a specific copy', 'ppl', 'description' )),
 ( 518, 'COPY_HOLDS_RECALL', oils_i18n_gettext( 518, 
    'Allow a user to place a cataloging recall on a specific copy', 'ppl', 'description' ));


-- Evergreen DB patch 0670.data.mark-email-and-phone-invalid.sql
--
-- Add org unit settings and standing penalty types to support
-- the mark email/phone invalid features.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0670', :eg_version);


INSERT INTO config.standing_penalty (id, name, label, staff_alert, org_depth) VALUES
    (
        31,
        'INVALID_PATRON_EMAIL_ADDRESS',
        oils_i18n_gettext(
            31,
            'Patron had an invalid email address',
            'csp',
            'label'
        ),
        TRUE,
        0
    ),
    (
        32,
        'INVALID_PATRON_DAY_PHONE',
        oils_i18n_gettext(
            32,
            'Patron had an invalid daytime phone number',
            'csp',
            'label'
        ),
        TRUE,
        0
    ),
    (
        33,
        'INVALID_PATRON_EVENING_PHONE',
        oils_i18n_gettext(
            33,
            'Patron had an invalid evening phone number',
            'csp',
            'label'
        ),
        TRUE,
        0
    ),
    (
        34,
        'INVALID_PATRON_OTHER_PHONE',
        oils_i18n_gettext(
            34,
            'Patron had an invalid other phone number',
            'csp',
            'label'
        ),
        TRUE,
        0
    );



SELECT evergreen.upgrade_deps_block_check('0671', :eg_version);

ALTER TABLE asset.copy_location
    ADD COLUMN checkin_alert BOOL NOT NULL DEFAULT FALSE;

-- Evergreen DB patch 0673.data.acq-cancel-reason-cleanup.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0673', :eg_version);

DELETE FROM
    acq.cancel_reason
WHERE
    -- any entries with id >= 2000 were added locally.  
    id < 2000 

    -- these cancel_reason's are actively used by the system
    AND id NOT IN (1, 2, 3, 1002, 1003, 1004, 1005, 1010, 1024, 1211, 1221, 1246, 1283)

    -- don't delete any cancel_reason's that may be in use locally
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.user_request WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.purchase_order WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.lineitem WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.lineitem_detail WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.acq_lineitem_history WHERE cancel_reason IS NOT NULL)
    AND id NOT IN (SELECT DISTINCT(cancel_reason) FROM acq.acq_purchase_order_history WHERE cancel_reason IS NOT NULL);


SELECT evergreen.upgrade_deps_block_check('0674', :eg_version);

ALTER TABLE config.copy_status
	  ADD COLUMN restrict_copy_delete BOOL NOT NULL DEFAULT FALSE;

UPDATE config.copy_status
SET restrict_copy_delete = TRUE
WHERE id IN (1,3,6,8);

INSERT INTO permission.perm_list (id, code, description) VALUES (
    520,
    'COPY_DELETE_WARNING.override',
    'Allow a user to override warnings about deleting copies in problematic situations.'
);


SELECT evergreen.upgrade_deps_block_check('0675', :eg_version);

-- set expected row count to low value to avoid problem
-- where use of this function by the circ tagging feature
-- results in full scans of asset.call_number
CREATE OR REPLACE FUNCTION action.usr_visible_circ_copies( INTEGER ) RETURNS SETOF BIGINT AS $$
    SELECT DISTINCT(target_copy) FROM action.usr_visible_circs($1)
$$ LANGUAGE SQL ROWS 10;


SELECT evergreen.upgrade_deps_block_check('0676', :eg_version);

INSERT INTO config.global_flag (name, label, enabled, value) VALUES (
    'opac.use_autosuggest',
    'OPAC: Show auto-completing suggestions dialog under basic search box (put ''opac_visible'' into the value field to limit suggestions to OPAC-visible items, or blank the field for a possible performance improvement)',
    TRUE,
    'opac_visible'
);

CREATE TABLE metabib.browse_entry (
    id BIGSERIAL PRIMARY KEY,
    value TEXT unique,
    index_vector tsvector
);
--Skip this, will be created differently later
--CREATE INDEX metabib_browse_entry_index_vector_idx ON metabib.browse_entry USING GIST (index_vector);
CREATE TRIGGER metabib_browse_entry_fti_trigger
    BEFORE INSERT OR UPDATE ON metabib.browse_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');


CREATE TABLE metabib.browse_entry_def_map (
    id BIGSERIAL PRIMARY KEY,
    entry BIGINT REFERENCES metabib.browse_entry (id),
    def INT REFERENCES config.metabib_field (id),
    source BIGINT REFERENCES biblio.record_entry (id)
);

ALTER TABLE config.metabib_field ADD COLUMN browse_field BOOLEAN DEFAULT TRUE NOT NULL;
ALTER TABLE config.metabib_field ADD COLUMN browse_xpath TEXT;

ALTER TABLE config.metabib_class ADD COLUMN bouyant BOOLEAN DEFAULT FALSE NOT NULL;
ALTER TABLE config.metabib_class ADD COLUMN restrict BOOLEAN DEFAULT FALSE NOT NULL;
ALTER TABLE config.metabib_field ADD COLUMN restrict BOOLEAN DEFAULT FALSE NOT NULL;

-- one good exception to default true:
UPDATE config.metabib_field
    SET browse_field = FALSE
    WHERE (field_class = 'keyword' AND name = 'keyword') OR
        (field_class = 'subject' AND name = 'complete');

-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
-- We're only touching it here to add a DELETE statement to the IF NEW.deleted
-- block.

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
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
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
                            COALESCE( quote_literal( attr_value ), 'NULL' ) ||
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
                UPDATE metabib.record_attr SET attrs = new_attrs WHERE id = NEW.id;
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

CREATE OR REPLACE FUNCTION metabib.browse_normalize(facet_text TEXT, mapped_field INT) RETURNS TEXT AS $$
DECLARE
    normalizer  RECORD;
BEGIN

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = mapped_field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( facet_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO facet_text;

    END LOOP;

    RETURN facet_text;
END;

$$ LANGUAGE PLPGSQL;

DROP FUNCTION biblio.extract_metabib_field_entry(bigint, text);
DROP FUNCTION biblio.extract_metabib_field_entry(bigint);

DROP TYPE metabib.field_entry_template;
CREATE TYPE metabib.field_entry_template AS (
        field_class     TEXT,
        field           INT,
        facet_field     BOOL,
        search_field    BOOL,
        browse_field   BOOL,
        source          BIGINT,
        value           TEXT
);


CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    browse_text TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            curr_text := ARRAY_TO_STRING(
                oils_xpath( '//text()',
                    REGEXP_REPLACE( -- This escapes all &s not followed by "amp;".  Data ise returned from oils_xpath (above) in UTF-8, not entity encoded
                        REGEXP_REPLACE( -- This escapes embeded <s
                            xml_node,
                            $re$(>[^<]+)(<)([^>]+<)$re$,
                            E'\\1&lt;\\3',
                            'g'
                        ),
                        '&(?!amp;)',
                        '&amp;',
                        'g'
                    )
                ),
                ' '
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));

                output_row.browse_field = TRUE;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
        END IF;

    END LOOP;

END;
$func$ LANGUAGE PLPGSQL;

-- default to a space joiner
CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( BIGINT ) RETURNS SETOF metabib.field_entry_template AS $func$
    SELECT * FROM biblio.extract_metabib_field_entry($1, ' ');
    $func$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        FOR fclass IN SELECT * FROM config.metabib_class LOOP
            -- RAISE NOTICE 'Emptying out %', fclass.name;
            EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
        END LOOP;
        DELETE FROM metabib.facet_entry WHERE source = bib_id;
        DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field THEN
            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = ind_data.value;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES
                    (metabib.browse_normalize(ind_data.value, ind_data.field));
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- This mimics a specific part of QueryParser, turning the first part of a
-- classed search (search_class) into a set of classes and possibly fields.
-- search_class might look like "author" or "title|proper" or "ti|uniform"
-- or "au" or "au|corporate|personal" or anything like that, where the first
-- element of the list you get by separating on the "|" character is either
-- a registered class (config.metabib_class) or an alias
-- (config.metabib_search_alias), and the rest of any such elements are
-- fields (config.metabib_field).
CREATE OR REPLACE
    FUNCTION metabib.search_class_to_registered_components(search_class TEXT)
    RETURNS SETOF RECORD AS $func$
DECLARE
    search_parts        TEXT[];
    field_name          TEXT;
    search_part_count   INTEGER;
    rec                 RECORD;
    registered_class    config.metabib_class%ROWTYPE;
    registered_alias    config.metabib_search_alias%ROWTYPE;
    registered_field    config.metabib_field%ROWTYPE;
BEGIN
    search_parts := REGEXP_SPLIT_TO_ARRAY(search_class, E'\\|');

    search_part_count := ARRAY_LENGTH(search_parts, 1);
    IF search_part_count = 0 THEN
        RETURN;
    ELSE
        SELECT INTO registered_class
            * FROM config.metabib_class WHERE name = search_parts[1];
        IF FOUND THEN
            IF search_part_count < 2 THEN   -- all fields
                rec := (registered_class.name, NULL::INTEGER);
                RETURN NEXT rec;
                RETURN; -- done
            END IF;
            FOR field_name IN SELECT *
                FROM UNNEST(search_parts[2:search_part_count]) LOOP
                SELECT INTO registered_field
                    * FROM config.metabib_field
                    WHERE name = field_name AND
                        field_class = registered_class.name;
                IF FOUND THEN
                    rec := (registered_class.name, registered_field.id);
                    RETURN NEXT rec;
                END IF;
            END LOOP;
        ELSE
            -- maybe we have an alias?
            SELECT INTO registered_alias
                * FROM config.metabib_search_alias WHERE alias=search_parts[1];
            IF NOT FOUND THEN
                RETURN;
            ELSE
                IF search_part_count < 2 THEN   -- return w/e the alias says
                    rec := (
                        registered_alias.field_class, registered_alias.field
                    );
                    RETURN NEXT rec;
                    RETURN; -- done
                ELSE
                    FOR field_name IN SELECT *
                        FROM UNNEST(search_parts[2:search_part_count]) LOOP
                        SELECT INTO registered_field
                            * FROM config.metabib_field
                            WHERE name = field_name AND
                                field_class = registered_alias.field_class;
                        IF FOUND THEN
                            rec := (
                                registered_alias.field_class,
                                registered_field.id
                            );
                            RETURN NEXT rec;
                        END IF;
                    END LOOP;
                END IF;
            END IF;
        END IF;
    END IF;
END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE
    FUNCTION metabib.suggest_browse_entries(
        query_text      TEXT,   -- 'foo' or 'foo & ba:*',ready for to_tsquery()
        search_class    TEXT,   -- 'alias' or 'class' or 'class|field..', etc
        headline_opts   TEXT,   -- markup options for ts_headline()
        visibility_org  INTEGER,-- null if you don't want opac visibility test
        query_limit     INTEGER,-- use in LIMIT clause of interal query
        normalization   INTEGER -- argument to TS_RANK_CD()
    ) RETURNS TABLE (
        value                   TEXT,   -- plain
        field                   INTEGER,
        bouyant_and_class_match BOOL,
        field_match             BOOL,
        field_weight            INTEGER,
        rank                    REAL,
        bouyant                 BOOL,
        match                   TEXT    -- marked up
    ) AS $func$
DECLARE
    query                   TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    query := TO_TSQUERY('keyword', query_text);

    IF visibility_org IS NOT NULL THEN
        opac_visibility_join := '
    JOIN asset.opac_visible_copies aovc ON (
        aovc.record = mbedm.source AND
        aovc.circ_lib IN (SELECT id FROM actor.org_unit_descendants($4))
    )';
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE 'SELECT *, TS_HEADLINE(value, $1, $3) FROM (SELECT DISTINCT
        mbe.value,
        cmf.id,
        cmc.bouyant AND _registered.field_class IS NOT NULL,
        _registered.field = cmf.id,
        cmf.weight,
        TS_RANK_CD(mbe.index_vector, $1, $6),
        cmc.bouyant
    FROM metabib.browse_entry_def_map mbedm
    JOIN metabib.browse_entry mbe ON (mbe.id = mbedm.entry)
    JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
    JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
    '  || search_class_join || opac_visibility_join ||
    ' WHERE $1 @@ mbe.index_vector
    ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
    LIMIT $5) x
    ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
    '   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization
        ;

    -- sort order:
    --  bouyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  bouyancy
    --  value itself

END;
$func$ LANGUAGE PLPGSQL;

-- The advantage of this over the stock regexp_split_to_array() is that it
-- won't degrade unicode strings.
CREATE OR REPLACE FUNCTION evergreen.regexp_split_to_array(TEXT, TEXT)
RETURNS TEXT[] AS $$
    return encode_array_literal([split $_[1], $_[0]]);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;


-- Adds some logic for browse_entry to split on non-word chars for index_vector, post-normalize
CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
BEGIN

    value := NEW.value;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;

        NEW.value := value;
    END IF;

    IF NEW.index_vector = ''::tsvector THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN
        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
    END IF;

    NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, value);

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Evergreen DB patch 0677.schema.circ_limits.sql
--
-- FIXME: insert description of change, if needed
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0677', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
-- Limit groups for circ counting
CREATE TABLE config.circ_limit_group (
    id          SERIAL  PRIMARY KEY,
    name        TEXT    UNIQUE NOT NULL,
    description TEXT
);

-- Limit sets
CREATE TABLE config.circ_limit_set (
    id          SERIAL  PRIMARY KEY,
    name        TEXT    UNIQUE NOT NULL,
    owning_lib  INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    items_out   INT     NOT NULL, -- Total current active circulations must be less than this. 0 means skip counting (always pass)
    depth       INT     NOT NULL DEFAULT 0, -- Depth count starts at
    global      BOOL    NOT NULL DEFAULT FALSE, -- If enabled, include everything below depth, otherwise ancestors/descendants only
    description TEXT
);

-- Linkage between matchpoints and limit sets
CREATE TABLE config.circ_matrix_limit_set_map (
    id          SERIAL  PRIMARY KEY,
    matchpoint  INT     NOT NULL REFERENCES config.circ_matrix_matchpoint (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    limit_set   INT     NOT NULL REFERENCES config.circ_limit_set (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    fallthrough BOOL    NOT NULL DEFAULT FALSE, -- If true fallthrough will grab this rule as it goes along
    active      BOOL    NOT NULL DEFAULT TRUE,
    CONSTRAINT circ_limit_set_once_per_matchpoint UNIQUE (matchpoint, limit_set)
);

-- Linkage between limit sets and circ mods
CREATE TABLE config.circ_limit_set_circ_mod_map (
    id          SERIAL  PRIMARY KEY,
    limit_set   INT     NOT NULL REFERENCES config.circ_limit_set (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    circ_mod    TEXT    NOT NULL REFERENCES config.circ_modifier (code) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT cm_once_per_set UNIQUE (limit_set, circ_mod)
);

-- Linkage between limit sets and limit groups
CREATE TABLE config.circ_limit_set_group_map (
    id          SERIAL  PRIMARY KEY,
    limit_set    INT     NOT NULL REFERENCES config.circ_limit_set (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    limit_group INT     NOT NULL REFERENCES config.circ_limit_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    check_only  BOOL    NOT NULL DEFAULT FALSE, -- If true, don't accumulate this limit_group for storing with the circulation
    CONSTRAINT clg_once_per_set UNIQUE (limit_set, limit_group)
);

-- Linkage between limit groups and circulations
CREATE TABLE action.circulation_limit_group_map (
    circ        BIGINT      NOT NULL REFERENCES action.circulation (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    limit_group INT         NOT NULL REFERENCES config.circ_limit_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (circ, limit_group)
);

-- Function for populating the circ/limit group mappings
CREATE OR REPLACE FUNCTION action.link_circ_limit_groups ( BIGINT, INT[] ) RETURNS VOID AS $func$
    INSERT INTO action.circulation_limit_group_map(circ, limit_group) SELECT $1, id FROM config.circ_limit_group WHERE id IN (SELECT * FROM UNNEST($2));
$func$ LANGUAGE SQL;

DROP TYPE IF EXISTS action.circ_matrix_test_result CASCADE;
CREATE TYPE action.circ_matrix_test_result AS ( success BOOL, fail_part TEXT, buildrows INT[], matchpoint INT, circulate BOOL, duration_rule INT, recurring_fine_rule INT, max_fine_rule INT, hard_due_date INT, renewals INT, grace_period INTERVAL, limit_groups INT[] );

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
    circ_limit_set          config.circ_limit_set%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
    result.success := TRUE;

    -- Need user info to look up matchpoints
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user AND NOT deleted;

    -- (Insta)Fail if we couldn't find the user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Need item info to look up matchpoints
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item AND NOT deleted;

    -- (Insta)Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
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

    -- (Insta)Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- All failures before this point are non-recoverable
    -- Below this point are possibly overridable failures

    -- Fail if the user is barred
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
    -- Alternately, fail if the item isn't checked out on a renewal
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

    -- Use Circ OU for penalties and such
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( circ_ou );

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

    -- Fail if the user has too many items out by defined limit sets
    FOR circ_limit_set IN SELECT ccls.* FROM config.circ_limit_set ccls
      JOIN config.circ_matrix_limit_set_map ccmlsm ON ccmlsm.limit_set = ccls.id
      WHERE ccmlsm.active AND ( ccmlsm.matchpoint = circ_matchpoint.id OR
        ( ccmlsm.matchpoint IN (SELECT * FROM unnest(result.buildrows)) AND ccmlsm.fallthrough )
        ) LOOP
            IF circ_limit_set.items_out > 0 AND NOT renewal THEN
                SELECT INTO context_org_list ARRAY_AGG(aou.id)
                  FROM actor.org_unit_full_path( circ_ou ) aou
                    JOIN actor.org_unit_type aout ON aou.ou_type = aout.id
                  WHERE aout.depth >= circ_limit_set.depth;
                IF circ_limit_set.global THEN
                    WITH RECURSIVE descendant_depth AS (
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                        WHERE ou.id IN (SELECT * FROM unnest(context_org_list))
                            UNION
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                            JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
                    ) SELECT INTO context_org_list ARRAY_AGG(ou.id) FROM actor.org_unit ou JOIN descendant_depth USING (id);
                END IF;
                SELECT INTO items_out COUNT(DISTINCT circ.id)
                  FROM action.circulation circ
                    JOIN asset.copy copy ON (copy.id = circ.target_copy)
                    LEFT JOIN action.circulation_limit_group_map aclgm ON (circ.id = aclgm.circ)
                  WHERE circ.usr = match_user
                    AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                    AND circ.checkin_time IS NULL
                    AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
                    AND (copy.circ_modifier IN (SELECT circ_mod FROM config.circ_limit_set_circ_mod_map WHERE limit_set = circ_limit_set.id)
                        OR aclgm.limit_group IN (SELECT limit_group FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id)
                    );
                IF items_out >= circ_limit_set.items_out THEN
                    result.fail_part := 'config.circ_matrix_circ_mod_test';
                    result.success := FALSE;
                    done := TRUE;
                    RETURN NEXT result;
                END IF;
            END IF;
            SELECT INTO result.limit_groups result.limit_groups || ARRAY_AGG(limit_group) FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id AND NOT check_only;
    END LOOP;

    -- If we passed everything, return the successful matchpoint
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

-- We need to re-create these, as they got dropped with the type above.
CREATE OR REPLACE FUNCTION action.item_user_circ_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, FALSE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.item_user_renew_test( INT, BIGINT, INT ) RETURNS SETOF action.circ_matrix_test_result AS $func$
    SELECT * FROM action.item_user_circ_test( $1, $2, $3, TRUE );
$func$ LANGUAGE SQL;

-- Temp function for migrating circ mod limits.
CREATE OR REPLACE FUNCTION evergreen.temp_migrate_circ_mod_limits() RETURNS VOID AS $func$
DECLARE
    circ_mod_group config.circ_matrix_circ_mod_test%ROWTYPE;
    current_set INT;
    circ_mod_count INT;
BEGIN
    FOR circ_mod_group IN SELECT * FROM config.circ_matrix_circ_mod_test LOOP
        INSERT INTO config.circ_limit_set(name, owning_lib, items_out, depth, global, description)
            SELECT org_unit || ' : Matchpoint ' || circ_mod_group.matchpoint || ' : Circ Mod Test ' || circ_mod_group.id, org_unit, circ_mod_group.items_out, 0, false, 'Migrated from Circ Mod Test System'
                FROM config.circ_matrix_matchpoint WHERE id = circ_mod_group.matchpoint
            RETURNING id INTO current_set;
        INSERT INTO config.circ_matrix_limit_set_map(matchpoint, limit_set, fallthrough, active) VALUES (circ_mod_group.matchpoint, current_set, false, true);
        INSERT INTO config.circ_limit_set_circ_mod_map(limit_set, circ_mod)
            SELECT current_set, circ_mod FROM config.circ_matrix_circ_mod_test_map WHERE circ_mod_test = circ_mod_group.id;
        SELECT INTO circ_mod_count count(id) FROM config.circ_limit_set_circ_mod_map WHERE limit_set = current_set;
        RAISE NOTICE 'Created limit set with id % and % circ modifiers attached to matchpoint %', current_set, circ_mod_count, circ_mod_group.matchpoint;
    END LOOP;
END;
$func$ LANGUAGE plpgsql;

-- Run the temp function
SELECT * FROM evergreen.temp_migrate_circ_mod_limits();

-- Drop the temp function
DROP FUNCTION evergreen.temp_migrate_circ_mod_limits();

--Drop the old tables
--Not sure we want to do this. Keeping them may help "something went wrong" correction.
--DROP TABLE IF EXISTS config.circ_matrix_circ_mod_test_map, config.circ_matrix_circ_mod_test;


-- Evergreen DB patch 0678.data.vandelay-default-merge-profiles.sql

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0678', :eg_version);

INSERT INTO vandelay.merge_profile (owner, name, replace_spec) 
    VALUES (1, 'Match-Only Merge', '901c');

INSERT INTO vandelay.merge_profile (owner, name, preserve_spec) 
    VALUES (1, 'Full Overlay', '901c');

-- Evergreen DB patch 0681.schema.user-activity.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0681', :eg_version);

-- SCHEMA --

CREATE TYPE config.usr_activity_group AS ENUM ('authen','authz','circ','hold','search');

CREATE TABLE config.usr_activity_type (
    id          SERIAL                      PRIMARY KEY, 
    ewho        TEXT,
    ewhat       TEXT,
    ehow        TEXT,
    label       TEXT                        NOT NULL, -- i18n
    egroup      config.usr_activity_group   NOT NULL,
    enabled     BOOL                        NOT NULL DEFAULT TRUE,
    transient   BOOL                        NOT NULL DEFAULT FALSE,
    CONSTRAINT  one_of_wwh CHECK (COALESCE(ewho,ewhat,ehow) IS NOT NULL)
);

CREATE UNIQUE INDEX unique_wwh ON config.usr_activity_type 
    (COALESCE(ewho,''), COALESCE (ewhat,''), COALESCE(ehow,''));

CREATE TABLE actor.usr_activity (
    id          BIGSERIAL   PRIMARY KEY,
    usr         INT         REFERENCES actor.usr (id) ON DELETE SET NULL,
    etype       INT         NOT NULL REFERENCES config.usr_activity_type (id),
    event_time  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- remove transient activity entries on insert of new entries
CREATE OR REPLACE FUNCTION actor.usr_activity_transient_trg () RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM actor.usr_activity act USING config.usr_activity_type atype
        WHERE atype.transient AND 
            NEW.etype = atype.id AND
            act.etype = atype.id AND
            act.usr = NEW.usr;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER remove_transient_usr_activity
    BEFORE INSERT ON actor.usr_activity
    FOR EACH ROW EXECUTE PROCEDURE actor.usr_activity_transient_trg();

-- given a set of activity criteria, find the most approprate activity type
CREATE OR REPLACE FUNCTION actor.usr_activity_get_type (
        ewho TEXT, 
        ewhat TEXT, 
        ehow TEXT
    ) RETURNS SETOF config.usr_activity_type AS $$
SELECT * FROM config.usr_activity_type 
    WHERE 
        enabled AND 
        (ewho  IS NULL OR ewho  = $1) AND
        (ewhat IS NULL OR ewhat = $2) AND
        (ehow  IS NULL OR ehow  = $3) 
    ORDER BY 
        -- BOOL comparisons sort false to true
        COALESCE(ewho, '')  != COALESCE($1, ''),
        COALESCE(ewhat,'')  != COALESCE($2, ''),
        COALESCE(ehow, '')  != COALESCE($3, '') 
    LIMIT 1;
$$ LANGUAGE SQL;

-- given a set of activity criteria, finds the best
-- activity type and inserts the activity entry
CREATE OR REPLACE FUNCTION actor.insert_usr_activity (
        usr INT,
        ewho TEXT, 
        ewhat TEXT, 
        ehow TEXT
    ) RETURNS SETOF actor.usr_activity AS $$
DECLARE
    new_row actor.usr_activity%ROWTYPE;
BEGIN
    SELECT id INTO new_row.etype FROM actor.usr_activity_get_type(ewho, ewhat, ehow);
    IF FOUND THEN
        new_row.usr := usr;
        INSERT INTO actor.usr_activity (usr, etype) 
            VALUES (usr, new_row.etype)
            RETURNING * INTO new_row;
        RETURN NEXT new_row;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- SEED DATA --

INSERT INTO config.usr_activity_type (id, ewho, ewhat, ehow, egroup, label) VALUES

     -- authen/authz actions
     -- note: "opensrf" is the default ingress/ehow
     (1,  NULL, 'login',  'opensrf',      'authen', oils_i18n_gettext(1 , 'Login via opensrf', 'cuat', 'label'))
    ,(2,  NULL, 'login',  'srfsh',        'authen', oils_i18n_gettext(2 , 'Login via srfsh', 'cuat', 'label'))
    ,(3,  NULL, 'login',  'gateway-v1',   'authen', oils_i18n_gettext(3 , 'Login via gateway-v1', 'cuat', 'label'))
    ,(4,  NULL, 'login',  'translator-v1','authen', oils_i18n_gettext(4 , 'Login via translator-v1', 'cuat', 'label'))
    ,(5,  NULL, 'login',  'xmlrpc',       'authen', oils_i18n_gettext(5 , 'Login via xmlrpc', 'cuat', 'label'))
    ,(6,  NULL, 'login',  'remoteauth',   'authen', oils_i18n_gettext(6 , 'Login via remoteauth', 'cuat', 'label'))
    ,(7,  NULL, 'login',  'sip2',         'authen', oils_i18n_gettext(7 , 'SIP2 Proxy Login', 'cuat', 'label'))
    ,(8,  NULL, 'login',  'apache',       'authen', oils_i18n_gettext(8 , 'Login via Apache module', 'cuat', 'label'))

    ,(9,  NULL, 'verify', 'opensrf',      'authz',  oils_i18n_gettext(9 , 'Verification via opensrf', 'cuat', 'label'))
    ,(10, NULL, 'verify', 'srfsh',        'authz',  oils_i18n_gettext(10, 'Verification via srfsh', 'cuat', 'label'))
    ,(11, NULL, 'verify', 'gateway-v1',   'authz',  oils_i18n_gettext(11, 'Verification via gateway-v1', 'cuat', 'label'))
    ,(12, NULL, 'verify', 'translator-v1','authz',  oils_i18n_gettext(12, 'Verification via translator-v1', 'cuat', 'label'))
    ,(13, NULL, 'verify', 'xmlrpc',       'authz',  oils_i18n_gettext(13, 'Verification via xmlrpc', 'cuat', 'label'))
    ,(14, NULL, 'verify', 'remoteauth',   'authz',  oils_i18n_gettext(14, 'Verification via remoteauth', 'cuat', 'label'))
    ,(15, NULL, 'verify', 'sip2',         'authz',  oils_i18n_gettext(15, 'SIP2 User Verification', 'cuat', 'label'))

     -- authen/authz actions w/ known uses of "who"
    ,(16, 'opac',        'login',  'gateway-v1',   'authen', oils_i18n_gettext(16, 'OPAC Login (jspac)', 'cuat', 'label'))
    ,(17, 'opac',        'login',  'apache',       'authen', oils_i18n_gettext(17, 'OPAC Login (tpac)', 'cuat', 'label'))
    ,(18, 'staffclient', 'login',  'gateway-v1',   'authen', oils_i18n_gettext(18, 'Staff Client Login', 'cuat', 'label'))
    ,(19, 'selfcheck',   'login',  'translator-v1','authen', oils_i18n_gettext(19, 'Self-Check Proxy Login', 'cuat', 'label'))
    ,(20, 'ums',         'login',  'xmlrpc',       'authen', oils_i18n_gettext(20, 'Unique Mgt Login', 'cuat', 'label'))
    ,(21, 'authproxy',   'login',  'apache',       'authen', oils_i18n_gettext(21, 'Apache Auth Proxy Login', 'cuat', 'label'))
    ,(22, 'libraryelf',  'login',  'xmlrpc',       'authz',  oils_i18n_gettext(22, 'LibraryElf Login', 'cuat', 'label'))

    ,(23, 'selfcheck',   'verify', 'translator-v1','authz',  oils_i18n_gettext(23, 'Self-Check User Verification', 'cuat', 'label'))
    ,(24, 'ezproxy',     'verify', 'remoteauth',   'authz',  oils_i18n_gettext(24, 'EZProxy Verification', 'cuat', 'label'))
    -- ...
    ;

-- reserve the first 1000 slots
SELECT SETVAL('config.usr_activity_type_id_seq'::TEXT, 1000);

INSERT INTO config.org_unit_setting_type 
    (name, label, description, grp, datatype) 
    VALUES (
        'circ.patron.usr_activity_retrieve.max',
         oils_i18n_gettext(
            'circ.patron.usr_activity_retrieve.max',
            'Max user activity entries to retrieve (staff client)',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'circ.patron.usr_activity_retrieve.max',
            'Sets the maxinum number of recent user activity entries to retrieve for display in the staff client.  0 means show none, -1 means show all.  Default is 1.',
            'coust', 
            'description'
        ),
        'gui',
        'integer'
    );


SELECT evergreen.upgrade_deps_block_check('0682', :eg_version);

CREATE TABLE asset.copy_location_group (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL, -- i18n
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    pos             INT     NOT NULL DEFAULT 0,
    top             BOOL    NOT NULL DEFAULT FALSE,
    opac_visible    BOOL    NOT NULL DEFAULT TRUE,
    CONSTRAINT lgroup_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE asset.copy_location_group_map (
    id       SERIAL PRIMARY KEY,
    location    INT     NOT NULL REFERENCES asset.copy_location (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    lgroup      INT     NOT NULL REFERENCES asset.copy_location_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT  lgroup_once_per_group UNIQUE (lgroup,location)
);

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0683', :eg_version);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (5, 'check_email_notify', 1);
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (7, 'check_email_notify', 1);
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (9, 'check_email_notify', 1);
INSERT INTO action_trigger.validator (module,description) VALUES
    ('HoldNotifyCheck',
    oils_i18n_gettext(
        'HoldNotifyCheck',
        'Check Hold notification flag(s)',
        'atval',
        'description'
    ));
UPDATE action_trigger.event_definition SET validator = 'HoldNotifyCheck' WHERE id = 9;

-- NOT COVERED: Adding check_sms_notify to the proper trigger. It doesn't have a static id.

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0684', :eg_version);

-- schema --

-- Replace the constraints with more flexible ENUM's
ALTER TABLE vandelay.queue DROP CONSTRAINT queue_queue_type_check;
ALTER TABLE vandelay.bib_queue DROP CONSTRAINT bib_queue_queue_type_check;
ALTER TABLE vandelay.authority_queue DROP CONSTRAINT authority_queue_queue_type_check;

CREATE TYPE vandelay.bib_queue_queue_type AS ENUM ('bib', 'acq');
CREATE TYPE vandelay.authority_queue_queue_type AS ENUM ('authority');

-- dropped column is also implemented by the child tables
ALTER TABLE vandelay.queue DROP COLUMN queue_type; 

-- to recover after using the undo sql from below
-- alter table vandelay.bib_queue  add column queue_type text default 'bib' not null;
-- alter table vandelay.authority_queue  add column queue_type text default 'authority' not null;

-- modify the child tables to use the ENUMs
ALTER TABLE vandelay.bib_queue 
    ALTER COLUMN queue_type DROP DEFAULT,
    ALTER COLUMN queue_type TYPE vandelay.bib_queue_queue_type 
        USING (queue_type::vandelay.bib_queue_queue_type),
    ALTER COLUMN queue_type SET DEFAULT 'bib';

ALTER TABLE vandelay.authority_queue 
    ALTER COLUMN queue_type DROP DEFAULT,
    ALTER COLUMN queue_type TYPE vandelay.authority_queue_queue_type 
        USING (queue_type::vandelay.authority_queue_queue_type),
    ALTER COLUMN queue_type SET DEFAULT 'authority';

-- give lineitems a pointer to their vandelay queued_record

ALTER TABLE acq.lineitem ADD COLUMN queued_record BIGINT
    REFERENCES vandelay.queued_bib_record (id) 
    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.acq_lineitem_history ADD COLUMN queued_record BIGINT
    REFERENCES vandelay.queued_bib_record (id) 
    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- seed data --

INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 
        521, 
        'IMPORT_ACQ_LINEITEM_BIB_RECORD_UPLOAD', 
        oils_i18n_gettext( 
            521,
            'Allows a user to create new bibs directly from an ACQ MARC file upload', 
            'ppl', 
            'description' 
        )
    );


INSERT INTO vandelay.import_error ( code, description ) 
    VALUES ( 
        'import.record.perm_failure', 
        oils_i18n_gettext(
            'import.record.perm_failure', 
            'Perm failure creating a record', 'vie', 'description') 
    );




-- Evergreen DB patch 0685.data.bluray_vr_format.sql
--
-- FIXME: insert description of change, if needed
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0685', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
DO $FUNC$
DECLARE
    same_marc BOOL;
BEGIN
    -- Check if it is already there
    PERFORM * FROM config.marc21_physical_characteristic_value_map v
        JOIN config.marc21_physical_characteristic_subfield_map s ON v.ptype_subfield = s.id
        WHERE s.ptype_key = 'v' AND s.subfield = 'e' AND s.start_pos = '4' AND s.length = '1'
            AND v.value = 's';

    -- If it is, bail.
    IF FOUND THEN
        RETURN;
    END IF;

    -- Otherwise, insert it
    INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label)
    SELECT 's',id,'Blu-ray'
        FROM config.marc21_physical_characteristic_subfield_map
        WHERE ptype_key = 'v' AND subfield = 'e' AND start_pos = '4' AND length = '1';

    -- And reingest the blue-ray items so that things see the new value
    SELECT INTO same_marc enabled FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';
    UPDATE config.internal_flag SET enabled = true WHERE name = 'ingest.reingest.force_on_same_marc';
    UPDATE biblio.record_entry SET marc=marc WHERE id IN (SELECT record
        FROM
            metabib.full_rec a JOIN metabib.full_rec b USING (record)
        WHERE
            a.tag = 'LDR' AND a.value LIKE '______g%'
        AND b.tag = '007' AND b.value LIKE 'v___s%');
    UPDATE config.internal_flag SET enabled = same_marc WHERE name = 'ingest.reingest.force_on_same_marc';
END;
$FUNC$;


-- Evergreen DB patch 0686.schema.auditor_boost.sql
--
-- FIXME: insert description of change, if needed
--
-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0686', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
-- These three functions are for capturing, getting, and clearing user and workstation information

-- Set the User AND workstation in one call. Tis faster. And less calls.
-- First argument is user, second is workstation
CREATE OR REPLACE FUNCTION auditor.set_audit_info(INT, INT) RETURNS VOID AS $$
    $_SHARED{"eg_audit_user"} = $_[0];
    $_SHARED{"eg_audit_ws"} = $_[1];
$$ LANGUAGE plperl;

-- Get the User AND workstation in one call. Less calls, useful for joins ;)
CREATE OR REPLACE FUNCTION auditor.get_audit_info() RETURNS TABLE (eg_user INT, eg_ws INT) AS $$
    return [{eg_user => $_SHARED{"eg_audit_user"}, eg_ws => $_SHARED{"eg_audit_ws"}}];
$$ LANGUAGE plperl;

-- Clear the audit info, for whatever reason
CREATE OR REPLACE FUNCTION auditor.clear_audit_info() RETURNS VOID AS $$
    delete($_SHARED{"eg_audit_user"});
    delete($_SHARED{"eg_audit_ws"});
$$ LANGUAGE plperl;

CREATE OR REPLACE FUNCTION auditor.create_auditor_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE auditor.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            audit_user  INT,
            audit_ws    INT,
            LIKE $$ || sch || $$.$$ || tbl || $$
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
        CREATE OR REPLACE FUNCTION auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO auditor.$$ || sch || $$_$$ || tbl || $$_history ( audit_id, audit_time, audit_action, audit_user, audit_ws, $$
            || array_to_string(column_list, ', ') || $$ )
                SELECT  nextval('auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq'),
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
        CREATE VIEW auditor.$$ || sch || $$_$$ || tbl || $$_lifecycle AS
            SELECT -1 AS audit_id,
                   now() AS audit_time,
                   '-' AS audit_action,
                   -1 AS audit_user,
                   -1 AS audit_ws,
                   $$ || array_to_string(column_list, ', ') || $$
              FROM $$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT audit_id, audit_time, audit_action, audit_user, audit_ws,
            $$ || array_to_string(column_list, ', ') || $$
              FROM auditor.$$ || sch || $$_$$ || tbl || $$_history;
    $$;
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

-- Corrects all column discrepencies between audit table and core table:
-- Adds missing columns
-- Removes leftover columns
-- Updates types
-- Also, ensures all core auditor columns exist.
CREATE OR REPLACE FUNCTION auditor.fix_columns() RETURNS VOID AS $BODY$
DECLARE
    current_table TEXT = ''; -- Storage for post-loop main table name
    current_audit_table TEXT = ''; -- Storage for post-loop audit table name
    query TEXT = ''; -- Storage for built query
    cr RECORD; -- column record object
    alter_t BOOL = false; -- Has the alter table command been appended yet
    auditor_cores TEXT[] = ARRAY[]::TEXT[]; -- Core auditor function list (filled inside of loop)
    core_column TEXT; -- The current core column we are adding
BEGIN
    FOR cr IN
        WITH audit_tables AS ( -- Basic grab of auditor tables. Anything in the auditor namespace, basically. With oids.
            SELECT c.oid AS audit_oid, c.relname AS audit_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind='r' AND nspname = 'auditor'
        ),
        table_set AS ( -- Union of auditor tables with their "main" tables. With oids.
            SELECT a.audit_oid, a.audit_table, c.oid AS main_oid, n.nspname as main_namespace, c.relname as main_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            JOIN audit_tables a ON a.audit_table = n.nspname || '_' || c.relname || '_history'
            WHERE relkind = 'r'
        ),
        column_lists AS ( -- All columns associated with the auditor or main table, grouped by the main table's oid.
            SELECT DISTINCT ON (main_oid, attname) t.main_oid, a.attname
            FROM table_set t
            JOIN pg_catalog.pg_attribute a ON a.attrelid IN (t.main_oid, t.audit_oid)
            WHERE attnum > 0 AND NOT attisdropped
        ),
        column_defs AS ( -- The motherload, every audit table and main table plus column names and defs.
            SELECT audit_table,
                   main_namespace,
                   main_table,
                   a.attname AS main_column, -- These two will be null for columns that have since been deleted, or for auditor core columns
                   pg_catalog.format_type(a.atttypid, a.atttypmod) AS main_column_def,
                   b.attname AS audit_column, -- These two will be null for columns that have since been added
                   pg_catalog.format_type(b.atttypid, b.atttypmod) AS audit_column_def
            FROM table_set t
            JOIN column_lists c USING (main_oid)
            LEFT JOIN pg_catalog.pg_attribute a ON a.attname = c.attname AND a.attrelid = t.main_oid AND a.attnum > 0 AND NOT a.attisdropped
            LEFT JOIN pg_catalog.pg_attribute b ON b.attname = c.attname AND b.attrelid = t.audit_oid AND b.attnum > 0 AND NOT b.attisdropped
        )
        -- Nice sorted output from the above
        SELECT * FROM column_defs WHERE main_column_def IS DISTINCT FROM audit_column_def ORDER BY main_namespace, main_table, main_column, audit_column
    LOOP
        IF current_table <> (cr.main_namespace || '.' || cr.main_table) THEN -- New table?
            FOR core_column IN SELECT DISTINCT unnest(auditor_cores) LOOP -- Update missing core auditor columns
                IF NOT alter_t THEN -- Add ALTER TABLE if we haven't already
                    query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                    alter_t:=TRUE;
                ELSE
                    query:=query || $$,$$;
                END IF;
                -- Bit of a sneaky bit here. Create audit_id as a bigserial so it gets automatic values and doesn't complain about nulls when becoming a PRIMARY KEY.
                query:=query || $$ ADD COLUMN $$ || CASE WHEN core_column = 'audit_id bigint' THEN $$audit_id bigserial PRIMARY KEY$$ ELSE core_column END;
            END LOOP;
            IF alter_t THEN -- Open alter table = needs a semicolon
                query:=query || $$; $$;
                alter_t:=FALSE;
                IF 'audit_id bigint' = ANY(auditor_cores) THEN -- We added a primary key...
                    -- Fun! Drop the default on audit_id, drop the auto-created sequence, create a new one, and set the current value
                    -- For added fun, we have to execute in chunks due to the parser checking setval/currval arguments at parse time.
                    EXECUTE query;
                    EXECUTE $$ALTER TABLE auditor.$$ || current_audit_table || $$ ALTER COLUMN audit_id DROP DEFAULT; $$ ||
                        $$CREATE SEQUENCE auditor.$$ || current_audit_table || $$_pkey_seq;$$;
                    EXECUTE $$SELECT setval('auditor.$$ || current_audit_table || $$_pkey_seq', currval('auditor.$$ || current_audit_table || $$_audit_id_seq')); $$ ||
                        $$DROP SEQUENCE auditor.$$ || current_audit_table || $$_audit_id_seq;$$;
                    query:='';
                END IF;
            END IF;
            -- New table means we reset the list of needed auditor core columns
            auditor_cores = ARRAY['audit_id bigint', 'audit_time timestamp with time zone', 'audit_action text', 'audit_user integer', 'audit_ws integer'];
            -- And store some values for use later, because we can't rely on cr in all places.
            current_table:=cr.main_namespace || '.' || cr.main_table;
            current_audit_table:=cr.audit_table;
        END IF;
        IF cr.main_column IS NULL AND cr.audit_column LIKE 'audit_%' THEN -- Core auditor column?
            -- Remove core from list of cores
            SELECT INTO auditor_cores array_agg(core) FROM unnest(auditor_cores) AS core WHERE core != (cr.audit_column || ' ' || cr.audit_column_def);
        ELSIF cr.main_column IS NULL THEN -- Main column doesn't exist, and it isn't an auditor column. Needs dropping from the auditor.
            IF NOT alter_t THEN
                query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                alter_t:=TRUE;
            ELSE
                query:=query || $$,$$;
            END IF;
            query:=query || $$ DROP COLUMN $$ || cr.audit_column;
        ELSIF cr.audit_column IS NULL AND cr.main_column IS NOT NULL THEN -- New column auditor doesn't have. Add it.
            IF NOT alter_t THEN
                query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                alter_t:=TRUE;
            ELSE
                query:=query || $$,$$;
            END IF;
            query:=query || $$ ADD COLUMN $$ || cr.main_column || $$ $$ || cr.main_column_def;
        ELSIF cr.main_column IS NOT NULL AND cr.audit_column IS NOT NULL THEN -- Both sides have this column, but types differ. Fix that.
            IF NOT alter_t THEN
                query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                alter_t:=TRUE;
            ELSE
                query:=query || $$,$$;
            END IF;
            query:=query || $$ ALTER COLUMN $$ || cr.audit_column || $$ TYPE $$ || cr.main_column_def;
        END IF;
    END LOOP;
    FOR core_column IN SELECT DISTINCT unnest(auditor_cores) LOOP -- Repeat this outside of the loop to catch the last table
        IF NOT alter_t THEN
            query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
            alter_t:=TRUE;
        ELSE
            query:=query || $$,$$;
        END IF;
        -- Bit of a sneaky bit here. Create audit_id as a bigserial so it gets automatic values and doesn't complain about nulls when becoming a PRIMARY KEY.
        query:=query || $$ ADD COLUMN $$ || CASE WHEN core_column = 'audit_id bigint' THEN $$audit_id bigserial PRIMARY KEY$$ ELSE core_column END;
    END LOOP;
    IF alter_t THEN -- Open alter table = needs a semicolon
        query:=query || $$;$$;
        IF 'audit_id bigint' = ANY(auditor_cores) THEN -- We added a primary key...
            -- Fun! Drop the default on audit_id, drop the auto-created sequence, create a new one, and set the current value
            -- For added fun, we have to execute in chunks due to the parser checking setval/currval arguments at parse time.
            EXECUTE query;
            EXECUTE $$ALTER TABLE auditor.$$ || current_audit_table || $$ ALTER COLUMN audit_id DROP DEFAULT; $$ ||
                $$CREATE SEQUENCE auditor.$$ || current_audit_table || $$_pkey_seq;$$;
            EXECUTE $$SELECT setval('auditor.$$ || current_audit_table || $$_pkey_seq', currval('auditor.$$ || current_audit_table || $$_audit_id_seq')); $$ ||
                $$DROP SEQUENCE auditor.$$ || current_audit_table || $$_audit_id_seq;$$;
            query:='';
        END IF;
    END IF;
    EXECUTE query;
END;
$BODY$ LANGUAGE plpgsql;

-- Update it all routine
CREATE OR REPLACE FUNCTION auditor.update_auditors() RETURNS boolean AS $BODY$
DECLARE
    auditor_name TEXT;
    table_schema TEXT;
    table_name TEXT;
BEGIN
    -- Drop Lifecycle view(s) before potential column changes
    FOR auditor_name IN
        SELECT c.relname
            FROM pg_catalog.pg_class c
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind = 'v' AND n.nspname = 'auditor' LOOP
        EXECUTE $$ DROP VIEW auditor.$$ || auditor_name || $$;$$;
    END LOOP;
    -- Fix all column discrepencies
    PERFORM auditor.fix_columns();
    -- Re-create trigger functions and lifecycle views
    FOR table_schema, table_name IN
        WITH audit_tables AS (
            SELECT c.oid AS audit_oid, c.relname AS audit_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind='r' AND nspname = 'auditor'
        ),
        table_set AS (
            SELECT a.audit_oid, a.audit_table, c.oid AS main_oid, n.nspname as main_namespace, c.relname as main_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            JOIN audit_tables a ON a.audit_table = n.nspname || '_' || c.relname || '_history'
            WHERE relkind = 'r'
        )
        SELECT main_namespace, main_table FROM table_set LOOP
        
        PERFORM auditor.create_auditor_func(table_schema, table_name);
        PERFORM auditor.create_auditor_lifecycle(table_schema, table_name);
    END LOOP;
    RETURN TRUE;
END;
$BODY$ LANGUAGE plpgsql;

-- Go ahead and update them all now
SELECT auditor.update_auditors();


-- Evergreen DB patch 0687.schema.enhance_reingest.sql
--
-- FIXME: insert description of change, if needed
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0687', :eg_version);
SELECT evergreen.upgrade_deps_block_check('0711', :eg_version); -- introduces
-- changes to metabib.reingest_metabib_field_entries() that must happen here
-- rather than later in a separate CREATE OR REPLACE FUNCTION statement.

-- FIXME: add/check SQL statements to perform the upgrade
-- New function def
CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    normalized_value    TEXT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.
            normalized_value := metabib.browse_normalize(
                ind_data.value, ind_data.field
            );

            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = normalized_value;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES (normalized_value);
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field AND NOT skip_search THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- Delete old one
DROP FUNCTION IF EXISTS metabib.reingest_metabib_field_entries(BIGINT);

-- Evergreen DB patch 0688.data.circ_history_export_csv.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0688', :eg_version);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.format.history.csv',
    'circ',
    oils_i18n_gettext(
        'circ.format.history.csv',
        'Produce CSV of circulation history',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.event_definition (
    active, owner, name, hook, reactor, validator, group_field, template) 
VALUES (
    TRUE, 1, 'Circ History CSV', 'circ.format.history.csv', 'ProcessTemplate', 'NOOP_True', 'usr',
$$
Title,Author,Call Number,Barcode,Format
[%-
FOR circ IN target;
    bibxml = helpers.unapi_bre(circ.target_copy.call_number.record, {flesh => '{mra}'});
    title = "";
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;
    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value') %]

    [%- helpers.csv_datum(title) -%],
    [%- helpers.csv_datum(author) -%],
    [%- helpers.csv_datum(circ.target_copy.call_number.label) -%],
    [%- helpers.csv_datum(circ.target_copy.barcode) -%],
    [%- helpers.csv_datum(item_type) %]
[%- END -%]
$$
);

INSERT INTO action_trigger.environment (event_def, path)
    VALUES (
        currval('action_trigger.event_definition_id_seq'),
        'target_copy.call_number'
    );


-- Evergreen DB patch 0689.data.record_print_format_update.sql
--
-- Updates print and email templates for bib record actions
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0689', :eg_version);

UPDATE action_trigger.event_definition SET template = $$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR item IN cbreb.items;
        bre_id = item.target_biblio_record_entry;

        bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
        FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
            title = title _ part.textContent;
        END;

        author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
        item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
        publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
        pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
        isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
        issn = bibxml.findnodes('//*[@tag="022"]/*[@code="a"]').textContent;
        upc = bibxml.findnodes('//*[@tag="024"]/*[@code="a"]').textContent;
        %]

        <li>
            Bib ID# [% bre_id %]<br/>
            [% IF isbn %]ISBN: [% isbn %]<br/>[% END %]
            [% IF issn %]ISSN: [% issn %]<br/>[% END %]
            [% IF upc  %]UPC:  [% upc %]<br/>[% END %]
            Title: [% title %]<br />
            Author: [% author %]<br />
            Publication Info: [% publisher %] [% pubdate %]<br/>
            Item Type: [% item_type %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$ 
WHERE hook = 'biblio.format.record_entry.print' AND id < 100; -- sample data


UPDATE action_trigger.event_definition SET delay = '00:00:00', template = $$
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Bibliographic Records

[% FOR cbreb IN target %]
[% FOR item IN cbreb.items;
    bre_id = item.target_biblio_record_entry;

    bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;

    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
    publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
    pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
    isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
    issn = bibxml.findnodes('//*[@tag="022"]/*[@code="a"]').textContent;
    upc = bibxml.findnodes('//*[@tag="024"]/*[@code="a"]').textContent;
%]

[% loop.count %]/[% loop.size %].  Bib ID# [% bre_id %] 
[% IF isbn %]ISBN: [% isbn _ "\n" %][% END -%]
[% IF issn %]ISSN: [% issn _ "\n" %][% END -%]
[% IF upc  %]UPC:  [% upc _ "\n" %] [% END -%]
Title: [% title %]
Author: [% author %]
Publication Info: [% publisher %] [% pubdate %]
Item Type: [% item_type %]

[% END %]
[% END %]
$$ 
WHERE hook = 'biblio.format.record_entry.email' AND id < 100; -- sample data

-- remove a swath of unused environment entries

DELETE FROM action_trigger.environment env 
    USING action_trigger.event_definition def 
    WHERE env.event_def = def.id AND 
        env.path != 'items' AND 
        def.hook = 'biblio.format.record_entry.print' AND 
        def.id < 100; -- sample data

DELETE FROM action_trigger.environment env 
    USING action_trigger.event_definition def 
    WHERE env.event_def = def.id AND 
        env.path != 'items' AND 
        env.path != 'owner' AND 
        def.hook = 'biblio.format.record_entry.email' AND 
        def.id < 100; -- sample data

-- Evergreen DB patch 0690.schema.unapi_limit_rank.sql
--
-- Rewrite the in-database unapi functions to include per-object limits and
-- offsets, such as a maximum number of copies and call numbers for given
-- bib record via the HSTORE syntax (for example, 'acn => 5, acp => 10' would
-- limit to a maximum of 5 call numbers for the bib, with up to 10 copies per
-- call number).
--
-- Add some notion of "preferred library" that will provide copy counts
-- and optionally affect the sorting of returned copies.
--
-- Sort copies by availability, preferring the most available copies.
--
-- Return located URIs.
--
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0690', :eg_version);

-- The simplest way to apply all of these changes is just to replace the unapi
-- schema entirely -- the following is a copy of 990.schema.unapi.sql with
-- the initial COMMIT in place in case the upgrade_deps_block_check fails;
-- if it does, then the attempt to create the unapi schema in the following
-- transaction will also fail. Not graceful, but safe!
DROP SCHEMA IF EXISTS unapi CASCADE;

CREATE SCHEMA unapi;

CREATE OR REPLACE FUNCTION evergreen.org_top()
RETURNS SETOF actor.org_unit AS $$
    SELECT * FROM actor.org_unit WHERE parent_ou IS NULL LIMIT 1;
$$ LANGUAGE SQL STABLE
ROWS 1;

CREATE OR REPLACE FUNCTION evergreen.array_remove_item_by_value(inp ANYARRAY, el ANYELEMENT)
RETURNS anyarray AS $$
    SELECT ARRAY_ACCUM(x.e) FROM UNNEST( $1 ) x(e) WHERE x.e <> $2;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.rank_ou(lib INT, search_lib INT, pref_lib INT DEFAULT NULL)
RETURNS INTEGER AS $$
    WITH search_libs AS (
        SELECT id, distance FROM actor.org_unit_descendants_distance($2)
    )
    SELECT COALESCE(
        (SELECT -10000 FROM actor.org_unit
         WHERE $1 = $3 AND id = $3 AND $2 IN (
                SELECT id FROM actor.org_unit WHERE parent_ou IS NULL
             )
        ),
        (SELECT distance FROM search_libs WHERE id = $1),
        10000
    );
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.rank_cp_status(status INT)
RETURNS INTEGER AS $$
    WITH totally_available AS (
        SELECT id, 0 AS avail_rank
        FROM config.copy_status
        WHERE opac_visible IS TRUE
            AND copy_active IS TRUE
            AND id != 1 -- "Checked out"
    ), almost_available AS (
        SELECT id, 10 AS avail_rank
        FROM config.copy_status
        WHERE holdable IS TRUE
            AND opac_visible IS TRUE
            AND copy_active IS FALSE
            OR id = 1 -- "Checked out"
    )
    SELECT COALESCE(
        (SELECT avail_rank FROM totally_available WHERE $1 IN (id)),
        (SELECT avail_rank FROM almost_available WHERE $1 IN (id)),
        100
    );
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT, 
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, aou.name, acn.label_sortkey,
            evergreen.rank_ou(aou.id, $2, $6), evergreen.rank_cp_status(acp.status),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN actor.org_unit_descendants( $2, COALESCE(
                $3, (
                    SELECT depth
                    FROM actor.org_unit_type aout
                        INNER JOIN actor.org_unit ou ON ou_type = aout.id
                    WHERE ou.id = $2
                ), $6)
            ) AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = $1
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
        GROUP BY acn.id, acp.status, aou.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY evergreen.rank_ou(aou.id, $2, $6), evergreen.rank_cp_status(acp.status)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$
LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.located_uris (
    bibid BIGINT, 
    ouid INT,
    pref_lib INT DEFAULT NULL
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank INT) AS $$
    SELECT acn.id, aou.name, acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number 
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           INNER JOIN actor.org_unit_ancestors( COALESCE($3, $2) ) aou ON (acn.owning_lib = aou.id)
      WHERE acn.record = $1
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE
    UNION
    SELECT acn.id, aou.name, acn.label_sortkey, evergreen.rank_ou(aou.id, $2, $3) AS pref_ou
      FROM asset.call_number acn
           INNER JOIN asset.uri_call_number_map auricnm ON acn.id = auricnm.call_number 
           INNER JOIN asset.uri auri ON auri.id = auricnm.uri
           INNER JOIN actor.org_unit_ancestors( $2 ) aou ON (acn.owning_lib = aou.id)
      WHERE acn.record = $1
          AND acn.deleted IS FALSE
          AND auri.active IS TRUE;
$$
LANGUAGE SQL STABLE;

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
CREATE OR REPLACE FUNCTION unapi.aou    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acnp   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acns   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acn    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.ssub   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sdist  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sstr   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sitem  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sunit  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sisum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sbsum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.sssum  ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.siss   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.auri   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acpn   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.acl    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.ccs    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.bre (
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
)
RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.bmp    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.mra    ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;
CREATE OR REPLACE FUNCTION unapi.circ   ( obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT DEFAULT '-', depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$ SELECT NULL::XML $F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.memoize (classname TEXT, obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

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
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', XMLATTRIBUTES( $1 AS xmlns), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.bre (
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
)
RETURNS XML AS $F$
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

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

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

    -- grab holdings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN 
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, evergreen.array_remove_item_by_value(includes,'holdings_xml'), slimit, soffset, include_xmlns, pref_lib);
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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ($5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
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
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($9,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT(
                            name monograph_parts,
                            (SELECT XMLAGG(bmp) FROM (
                                SELECT  unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE)
                                  FROM  biblio.monograph_part
                                  WHERE record = $1
                            )x)
                        )
                     ELSE NULL
                 END,
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes($1, $2, $4, $6, $7, $9) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), 0, name, label_sortkey
                        FROM evergreen.located_uris($1, $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN 
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
                            SELECT  unapi.acp(p.target_copy,'xml','copy',evergreen.array_remove_item_by_value($5,'acp'), $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND p.peer_record = $1
                            LIMIT ($6 -> 'acp')::INT
                            OFFSET ($7 -> 'acp')::INT
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.ssub ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name subscription,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@ssub/' || id AS id,
                        'tag:open-ils.org:U2@aou/' || owning_lib AS owning_lib,
                        start_date AS start, end_date AS end, expected_date_offset
                    ),
                    CASE 
                        WHEN ('sdist' = ANY ($4)) THEN
                            XMLELEMENT( name distributions,
                                (SELECT XMLAGG(sdist) FROM (
                                    SELECT  unapi.sdist( id, 'xml', 'distribution', evergreen.array_remove_item_by_value($4,'ssub'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.distribution
                                      WHERE subscription = ssub.id
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  serial.subscription ssub
          WHERE id = $1
          GROUP BY id, start_date, end_date, expected_date_offset, owning_lib;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sdist ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
                    CASE 
                        WHEN ('sstr' = ANY ($4)) THEN
                            XMLELEMENT( name streams,
                                (SELECT XMLAGG(sstr) FROM (
                                    SELECT  unapi.sstr( id, 'xml', 'stream', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.stream
                                      WHERE distribution = sdist.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    XMLELEMENT( name summaries,
                        CASE 
                            WHEN ('sbsum' = ANY ($4)) THEN
                                (SELECT XMLAGG(sbsum) FROM (
                                    SELECT  unapi.sbsum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.basic_summary
                                      WHERE distribution = sdist.id
                                )x)
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('sisum' = ANY ($4)) THEN
                                (SELECT XMLAGG(sisum) FROM (
                                    SELECT  unapi.sisum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.index_summary
                                      WHERE distribution = sdist.id
                                )x)
                            ELSE NULL
                        END,
                        CASE 
                            WHEN ('sssum' = ANY ($4)) THEN
                                (SELECT XMLAGG(sssum) FROM (
                                    SELECT  unapi.sssum( id, 'xml', 'serial_summary', evergreen.array_remove_item_by_value($4,'sdist'), $5, $6, $7, $8, FALSE)
                                      FROM  serial.supplement_summary
                                      WHERE distribution = sdist.id
                                )x)
                            ELSE NULL
                        END
                    )
                )
          FROM  serial.distribution sdist
          WHERE id = $1
          GROUP BY id, label, unit_label_prefix, unit_label_suffix, holding_lib, summary_method, subscription, receive_call_number, bind_call_number;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sstr ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name stream,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@sstr/' || id AS id,
                    routing_label
                ),
                CASE WHEN distribution IS NOT NULL AND ('sdist' = ANY ($4)) THEN unapi.sssum( distribution, 'xml', 'distribtion', evergreen.array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                CASE 
                    WHEN ('sitem' = ANY ($4)) THEN
                        XMLELEMENT( name items,
                            (SELECT XMLAGG(sitem) FROM (
                                SELECT  unapi.sitem( id, 'xml', 'serial_item', evergreen.array_remove_item_by_value($4,'sstr'), $5, $6, $7, $8, FALSE)
                                  FROM  serial.item
                                  WHERE stream = sstr.id
                            )x)
                        )
                    ELSE NULL
                END
            )
      FROM  serial.stream sstr
      WHERE id = $1
      GROUP BY id, routing_label, distribution;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.siss ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name issuance,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    'tag:open-ils.org:U2@siss/' || id AS id,
                    create_date, edit_date, label, date_published,
                    holding_code, holding_type, holding_link_id
                ),
                CASE WHEN subscription IS NOT NULL AND ('ssub' = ANY ($4)) THEN unapi.ssub( subscription, 'xml', 'subscription', evergreen.array_remove_item_by_value($4,'siss'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                CASE 
                    WHEN ('sitem' = ANY ($4)) THEN
                        XMLELEMENT( name items,
                            (SELECT XMLAGG(sitem) FROM (
                                SELECT  unapi.sitem( id, 'xml', 'serial_item', evergreen.array_remove_item_by_value($4,'siss'), $5, $6, $7, $8, FALSE)
                                  FROM  serial.item
                                  WHERE issuance = sstr.id
                            )x)
                        )
                    ELSE NULL
                END
            )
      FROM  serial.issuance sstr
      WHERE id = $1
      GROUP BY id, create_date, edit_date, label, date_published, holding_code, holding_type, holding_link_id, subscription;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sitem ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
                    CASE WHEN unit IS NOT NULL AND ('sunit' = ANY ($4)) THEN unapi.sunit( unit, $2, 'serial_unit', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE WHEN uri IS NOT NULL AND ('auri' = ANY ($4)) THEN unapi.auri( uri, $2, 'uri', evergreen.array_remove_item_by_value($4,'sitem'), $5, $6, $7, $8, FALSE) ELSE NULL END
--                    XMLELEMENT( name notes,
--                        CASE 
--                            WHEN ('acpn' = ANY ($4)) THEN
--                                (SELECT XMLAGG(acpn) FROM (
--                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8)
--                                      FROM  asset.copy_note
--                                      WHERE owning_copy = cp.id AND pub
--                                )x)
--                            ELSE NULL
--                        END
--                    )
                )
          FROM  serial.item sitem
          WHERE id = $1;
$F$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION unapi.sssum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sbsum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sisum ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;


CREATE OR REPLACE FUNCTION unapi.aou ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acl ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name location,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident,
                    holdable,
                    opac_visible,
                    label_prefix AS prefix,
                    label_suffix AS suffix
                ),
                name
            )
      FROM  asset.copy_location
      WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.ccs ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
                name status,
                XMLATTRIBUTES(
                    CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    id AS ident,
                    holdable,
                    opac_visible
                ),
                name
            )
      FROM  config.copy_status
      WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acpn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.ascecm ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.bmp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
                                          AND cp.deleted IS FALSE
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT ($7 -> 'acp')::INT
                                      OFFSET ($8 -> 'acp')::INT

                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8, FALSE) ELSE NULL END
                )
          FROM  biblio.monograph_part
          WHERE id = $1
          GROUP BY id, label, label_sortkey, record;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id, id AS copy_id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, age_protect
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE 
                        WHEN ('acpn' = ANY ($4)) THEN
                            XMLELEMENT( name copy_notes,
                                (SELECT XMLAGG(acpn) FROM (
                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_note
                                      WHERE owning_copy = cp.id AND pub
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('ascecm' = ANY ($4)) THEN
                            XMLELEMENT( name statcats,
                                (SELECT XMLAGG(ascecm) FROM (
                                    SELECT  unapi.ascecm( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.stat_cat_entry_copy_map
                                      WHERE owning_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('bre' = ANY ($4)) THEN
                            XMLELEMENT( name foreign_records,
                                (SELECT XMLAGG(bre) FROM (
                                    SELECT  unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE)
                                      FROM  biblio.peer_bib_copy_map
                                      WHERE target_copy = cp.id
                                )x)

                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                (SELECT XMLAGG(bmp) FROM (
                                    SELECT  unapi.bmp( part, 'xml', 'monograph_part', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_part_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('circ' = ANY ($4)) THEN
                            XMLELEMENT( name current_circulation,
                                (SELECT XMLAGG(circ) FROM (
                                    SELECT  unapi.circ( id, 'xml', 'circ', evergreen.array_remove_item_by_value($4,'circ'), $5, $6, $7, $8, FALSE)
                                      FROM  action.circulation
                                      WHERE target_copy = cp.id
                                            AND checkin_time IS NULL
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
              AND cp.deleted IS FALSE
          GROUP BY id, status, location, circ_lib, call_number, create_date,
              edit_date, copy_number, circulate, deposit, ref, holdable,
              deleted, deposit_amount, price, barcode, circ_modifier,
              circ_as_type, opac_visible, age_protect;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sunit ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_unit,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id, id AS copy_id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, age_protect,
                        status_changed_time, floating, mint_condition,
                        detailed_contents, sort_key, summary_contents, cost 
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                (SELECT XMLAGG(acpn) FROM (
                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_note
                                      WHERE owning_copy = cp.id AND pub
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                (SELECT XMLAGG(ascecm) FROM (
                                    SELECT  unapi.ascecm( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.stat_cat_entry_copy_map
                                      WHERE owning_copy = cp.id
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name foreign_records,
                        CASE
                            WHEN ('bre' = ANY ($4)) THEN
                                (SELECT XMLAGG(bre) FROM (
                                    SELECT  unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE)
                                      FROM  biblio.peer_bib_copy_map
                                      WHERE target_copy = cp.id
                                )x)
                            ELSE NULL
                        END
                    ),
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                (SELECT XMLAGG(bmp) FROM (
                                    SELECT  unapi.bmp( part, 'xml', 'monograph_part', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_part_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE 
                        WHEN ('circ' = ANY ($4)) THEN
                            XMLELEMENT( name current_circulation,
                                (SELECT XMLAGG(circ) FROM (
                                    SELECT  unapi.circ( id, 'xml', 'circ', evergreen.array_remove_item_by_value($4,'circ'), $5, $6, $7, $8, FALSE)
                                      FROM  action.circulation
                                      WHERE target_copy = cp.id
                                            AND checkin_time IS NULL
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  serial.unit cp
          WHERE id = $1
              AND cp.deleted IS FALSE
          GROUP BY id, status, location, circ_lib, call_number, create_date,
              edit_date, copy_number, circulate, floating, mint_condition,
              deposit, ref, holdable, deleted, deposit_amount, price,
              barcode, circ_modifier, circ_as_type, opac_visible,
              status_changed_time, detailed_contents, sort_key,
              summary_contents, cost, age_protect;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        acn.id AS vol_id, o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            CASE WHEN $6 IS NOT NULL THEN
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                                            evergreen.rank_cp_status(cp.status) AS rank_avail
                                          FROM  asset.copy cp
                                                JOIN actor.org_unit_descendants( (SELECT id FROM actor.org_unit WHERE shortname = $5), $6) aoud ON (cp.circ_lib = aoud.id)
                                          WHERE cp.call_number = acn.id
                                              AND cp.deleted IS FALSE
                                          ORDER BY rank_avail, COALESCE(cp.copy_number,0), cp.barcode
                                          LIMIT ($7 -> 'acp')::INT
                                          OFFSET ($8 -> 'acp')::INT
                                    )x)
                                )
                            ELSE
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                                            evergreen.rank_cp_status(cp.status) AS rank_avail
                                          FROM  asset.copy cp
                                                JOIN actor.org_unit_descendants( (SELECT id FROM actor.org_unit WHERE shortname = $5) ) aoud ON (cp.circ_lib = aoud.id)
                                          WHERE cp.call_number = acn.id
                                              AND cp.deleted IS FALSE
                                          ORDER BY rank_avail, COALESCE(cp.copy_number,0), cp.barcode
                                          LIMIT ($7 -> 'acp')::INT
                                          OFFSET ($8 -> 'acp')::INT
                                    )x)
                                )
                            END
                        ELSE NULL
                    END,
                    XMLELEMENT(
                        name uris,
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    unapi.acnp( acn.prefix, 'marcxml', 'prefix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                    unapi.acns( acn.suffix, 'marcxml', 'suffix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
              AND acn.deleted IS FALSE
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acnp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_prefix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        'tag:open-ils.org:U2@aou/' || owning_lib AS owning_lib,
                        label_sortkey
                    )
                )
          FROM  asset.call_number_prefix
          WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acns ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_suffix,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        id AS ident,
                        label,
                        'tag:open-ils.org:U2@aou/' || owning_lib AS owning_lib,
                        label_sortkey
                    )
                )
          FROM  asset.call_number_suffix
          WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.auri ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name uri,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@auri/' || uri.id AS id,
                        use_restriction,
                        href,
                        label
                    ),
                    CASE 
                        WHEN ('acn' = ANY ($4)) THEN
                            XMLELEMENT( name copies,
                                (SELECT XMLAGG(acn) FROM (SELECT unapi.acn( call_number, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'auri'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE uri = uri.id)x)
                            )
                        ELSE NULL
                    END
                ) AS x
          FROM  asset.uri uri
          WHERE uri.id = $1
          GROUP BY uri.id, use_restriction, href, label;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.mra ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
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
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.circ (obj_id BIGINT, format TEXT, ename TEXT, includes TEXT[], org TEXT DEFAULT '-', depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
    SELECT XMLELEMENT(
        name circ,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@circ/' || id AS id,
            xact_start,
            due_date
        ),
        CASE WHEN ('aou' = ANY ($4)) THEN unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value($4,'circ'), $5, $6, $7, $8, FALSE) ELSE NULL END,
        CASE WHEN ('acp' = ANY ($4)) THEN unapi.acp( circ_lib, $2, 'target_copy', evergreen.array_remove_item_by_value($4,'circ'), $5, $6, $7, $8, FALSE) ELSE NULL END
    )
    FROM action.circulation
    WHERE id = $1;
$F$ LANGUAGE SQL STABLE;

/*

 -- Some test queries

SELECT unapi.memoize( 'bre', 1,'mods32','','{holdings_xml,acp}'::TEXT[], 'SYS1');
SELECT unapi.memoize( 'bre', 1,'marcxml','','{holdings_xml,acp}'::TEXT[], 'SYS1');
SELECT unapi.memoize( 'bre', 1,'holdings_xml','','{holdings_xml,acp}'::TEXT[], 'SYS1');

SELECT unapi.biblio_record_entry_feed('{1}'::BIGINT[],'mods32','{holdings_xml,acp}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://c64/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');

SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'marcxml','{holdings_xml}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');
EXPLAIN ANALYZE SELECT unapi.biblio_record_entry_feed('{7209,7394}'::BIGINT[],'mods32','{holdings_xml}'::TEXT[],'SYS1',NULL,'acn=>1',NULL, NULL,NULL,NULL,NULL,'http://fulfillment2.esilibrary.com/opac/extras/unapi', '<totalResults xmlns="http://a9.com/-/spec/opensearch/1.1/">2</totalResults><startIndex xmlns="http://a9.com/-/spec/opensearch/1.1/">1</startIndex><itemsPerPage xmlns="http://a9.com/-/spec/opensearch/1.1/">10</itemsPerPage>');

SELECT unapi.biblio_record_entry_feed('{216}'::BIGINT[],'marcxml','{}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.bre(216,'marcxml','record','{holdings_xml,bre.unapi}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.bre(216,'holdings_xml','record','{}'::TEXT[], 'BR1');
EXPLAIN ANALYZE SELECT unapi.holdings_xml(216,4,'BR1',2,'{bre}'::TEXT[]);
EXPLAIN ANALYZE SELECT unapi.bre(216,'mods32','record','{}'::TEXT[], 'BR1');

-- Limit to 5 call numbers, 5 copies, with a preferred library of 4 (BR1), in SYS2 at a depth of 0
EXPLAIN ANALYZE SELECT unapi.bre(36,'marcxml','record','{holdings_xml,mra,acp,acnp,acns,bmp}','SYS2',0,'acn=>5,acp=>5',NULL,TRUE,4);

*/


SELECT evergreen.upgrade_deps_block_check('0692', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
    VALUES (
        'circ.fines.charge_when_closed',
         oils_i18n_gettext(
            'circ.fines.charge_when_closed',
            'Charge fines on overdue circulations when closed',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.fines.charge_when_closed',
            'Normally, fines are not charged when a library is closed.  When set to True, fines will be charged during scheduled closings and normal weekly closed days.',
            'coust',
            'description'
        ),
        'circ',
        'bool'
    );

SELECT evergreen.upgrade_deps_block_check('0694', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

( 'ui.patron.edit.au.prefix.require', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.prefix.require',
        'Require prefix field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.prefix.require',
        'The prefix field will be required on the patron registration screen.',
        'coust', 'description'),
    'bool', null)
	
,( 'ui.patron.edit.au.prefix.show', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.prefix.show',
        'Show prefix field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.prefix.show',
        'The prefix field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.',
        'coust', 'description'),
    'bool', null)

,( 'ui.patron.edit.au.prefix.suggest', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.prefix.suggest',
        'Suggest prefix field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.prefix.suggest',
        'The prefix field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.',
        'coust', 'description'),
    'bool', null)
;		


-- Evergreen DB patch 0695.schema.custom_toolbars.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0695', :eg_version);

CREATE TABLE actor.toolbar (
    id          BIGSERIAL   PRIMARY KEY,
    ws          INT         REFERENCES actor.workstation (id) ON DELETE CASCADE,
    org         INT         REFERENCES actor.org_unit (id) ON DELETE CASCADE,
    usr         INT         REFERENCES actor.usr (id) ON DELETE CASCADE,
    label       TEXT        NOT NULL,
    layout      TEXT        NOT NULL,
    CONSTRAINT only_one_type CHECK (
        (ws IS NOT NULL AND COALESCE(org,usr) IS NULL) OR
        (org IS NOT NULL AND COALESCE(ws,usr) IS NULL) OR
        (usr IS NOT NULL AND COALESCE(org,ws) IS NULL)
    ),
    CONSTRAINT layout_must_be_json CHECK ( is_json(layout) )
);
CREATE UNIQUE INDEX label_once_per_ws ON actor.toolbar (ws, label) WHERE ws IS NOT NULL;
CREATE UNIQUE INDEX label_once_per_org ON actor.toolbar (org, label) WHERE org IS NOT NULL;
CREATE UNIQUE INDEX label_once_per_usr ON actor.toolbar (usr, label) WHERE usr IS NOT NULL;

-- this one unrelated to toolbars but is a gap in the upgrade scripts
INSERT INTO permission.perm_list ( id, code, description )
    SELECT
        522,
        'IMPORT_AUTHORITY_MARC',
        oils_i18n_gettext(
            522,
            'Allows a user to create new authority records',
            'ppl',
            'description'
        )
    WHERE NOT EXISTS (
        SELECT 1
        FROM permission.perm_list
        WHERE
            id = 522
    );

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    523,
    'ADMIN_TOOLBAR',
    oils_i18n_gettext(
        523,
        'Allows a user to create, edit, and delete custom toolbars',
        'ppl',
        'description'
    )
);

-- Don't want to assume stock perm groups in an upgrade script, but here for ease of testing
-- INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable) SELECT pgt.id, perm.id, aout.depth, FALSE FROM permission.grp_tree pgt, permission.perm_list perm, actor.org_unit_type aout WHERE pgt.name = 'Staff' AND aout.name = 'Branch' AND perm.code = 'ADMIN_TOOLBAR';

INSERT INTO actor.toolbar(org,label,layout) VALUES
    ( 1, 'circ', '["circ_checkout","circ_checkin","toolbarseparator.1","search_opac","copy_status","toolbarseparator.2","patron_search","patron_register","toolbarspacer.3","hotkeys_toggle"]' ),
    ( 1, 'cat', '["circ_checkin","toolbarseparator.1","search_opac","copy_status","toolbarseparator.2","create_marc","authority_manage","retrieve_last_record","toolbarspacer.3","hotkeys_toggle"]' );

-- delete from permission.grp_perm_map where perm in (select id from permission.perm_list where code ~ 'TOOLBAR'); delete from permission.perm_list where code ~ 'TOOLBAR'; drop table actor.toolbar ;

-- Evergreen DB patch 0696.no_plperl.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0696', :eg_version);

-- Re-create these as plperlu instead of plperl
CREATE OR REPLACE FUNCTION auditor.set_audit_info(INT, INT) RETURNS VOID AS $$
    $_SHARED{"eg_audit_user"} = $_[0];
    $_SHARED{"eg_audit_ws"} = $_[1];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION auditor.get_audit_info() RETURNS TABLE (eg_user INT, eg_ws INT) AS $$
    return [{eg_user => $_SHARED{"eg_audit_user"}, eg_ws => $_SHARED{"eg_audit_ws"}}];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION auditor.clear_audit_info() RETURNS VOID AS $$
    delete($_SHARED{"eg_audit_user"});
    delete($_SHARED{"eg_audit_ws"});
$$ LANGUAGE plperlu;

-- Evergreen DB patch 0697.data.place_currently_unfillable_hold.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0697', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 524, 'PLACE_UNFILLABLE_HOLD', oils_i18n_gettext( 524,
    'Allows a user to place a hold that cannot currently be filled.', 'ppl', 'description' ));

-- Evergreen DB patch 0698.hold_default_pickup.sql
--
-- FIXME: insert description of change, if needed
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0698', :eg_version);

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_pickup_location', TRUE, 'Default Hold Pickup Location', 'Default location for holds pickup', 'integer');

SELECT evergreen.upgrade_deps_block_check('0699', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, grp )
    VALUES (
        'ui.hide_copy_editor_fields',
        oils_i18n_gettext(
            'ui.hide_copy_editor_fields',
            'GUI: Hide these fields within the Item Attribute Editor',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.hide_copy_editor_fields',
            'This setting may be best maintained with the dedicated configuration'
            || ' interface within the Item Attribute Editor.  However, here it'
            || ' shows up as comma separated list of field identifiers to hide.',
            'coust',
            'description'
        ),
        'array',
        'gui'
    );


SELECT evergreen.upgrade_deps_block_check('0700', :eg_version);
SELECT evergreen.upgrade_deps_block_check('0706', :eg_version);
SELECT evergreen.upgrade_deps_block_check('0710', :eg_version);


CREATE OR REPLACE FUNCTION evergreen.could_be_serial_holding_code(TEXT) RETURNS BOOL AS $$
    use JSON::XS;
    use MARC::Field;

    eval {
        my $holding_code = (new JSON::XS)->decode(shift);
        new MARC::Field('999', @$holding_code);
    };  
    return $@ ? 0 : 1;
$$ LANGUAGE PLPERLU;

-- This throws away data, but only data that causes breakage anyway.
UPDATE serial.issuance SET holding_code = NULL WHERE NOT could_be_serial_holding_code(holding_code);

-- If we don't do this, we have unprocessed triggers and we can't alter the table
SET CONSTRAINTS serial.issuance_caption_and_pattern_fkey IMMEDIATE;

ALTER TABLE serial.issuance
    DROP CONSTRAINT IF EXISTS issuance_holding_code_check;

ALTER TABLE serial.issuance ADD CHECK (holding_code IS NULL OR could_be_serial_holding_code(holding_code));

INSERT INTO config.internal_flag (name, value, enabled) VALUES (
    'serial.rematerialize_on_same_holding_code', NULL, FALSE
);

INSERT INTO config.org_unit_setting_type (
    name, label, grp, description, datatype
) VALUES (
    'serial.default_display_grouping',
    'Default display grouping for serials distributions presented in the OPAC.',
    'serial',
    'Default display grouping for serials distributions presented in the OPAC. This can be "enum" or "chron".',
    'string'
);

ALTER TABLE serial.distribution
    ADD COLUMN display_grouping TEXT NOT NULL DEFAULT 'chron'
        CHECK (display_grouping IN ('enum', 'chron'));

-- why didn't we just make one summary table in the first place?
CREATE VIEW serial.any_summary AS
    SELECT
        'basic' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.basic_summary
    UNION
    SELECT
        'index' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.index_summary
    UNION
    SELECT
        'supplement' AS summary_type, id, distribution,
        generated_coverage, textual_holdings, show_generated
    FROM serial.supplement_summary ;


-- Given the IDs of two rows in actor.org_unit, *the second being an ancestor
-- of the first*, return in array form the path from the ancestor to the
-- descendant, with each point in the path being an org_unit ID.  This is
-- useful for sorting org_units by their position in a depth-first (display
-- order) representation of the tree.
--
-- This breaks with the precedent set by actor.org_unit_full_path() and others,
-- and gets the parameters "backwards," but otherwise this function would
-- not be very usable within json_query.
CREATE OR REPLACE FUNCTION actor.org_unit_simple_path(INT, INT)
RETURNS INT[] AS $$
    WITH RECURSIVE descendant_depth(id, path) AS (
        SELECT  aou.id,
                ARRAY[aou.id]
          FROM  actor.org_unit aou
                JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
          WHERE aou.id = $2
            UNION ALL
        SELECT  aou.id,
                dd.path || ARRAY[aou.id]
          FROM  actor.org_unit aou
                JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
                JOIN descendant_depth dd ON (dd.id = aou.parent_ou)
    ) SELECT dd.path
        FROM actor.org_unit aou
        JOIN descendant_depth dd USING (id)
        WHERE aou.id = $1 ORDER BY dd.path;
$$ LANGUAGE SQL STABLE;

CREATE TABLE serial.materialized_holding_code (
    id BIGSERIAL PRIMARY KEY,
    issuance INTEGER NOT NULL REFERENCES serial.issuance (id) ON DELETE CASCADE,
    subfield CHAR,
    value TEXT
);

CREATE OR REPLACE FUNCTION serial.materialize_holding_code() RETURNS TRIGGER
AS $func$ 
use strict;

use MARC::Field;
use JSON::XS;

if (not defined $_TD->{new}{holding_code}) {
    elog(WARNING, 'NULL in "holding_code" column of serial.issuance allowed for now, but may not be useful');
    return;
}

# Do nothing if holding_code has not changed...

if ($_TD->{new}{holding_code} eq $_TD->{old}{holding_code}) {
    # ... unless the following internal flag is set.

    my $flag_rv = spi_exec_query(q{
        SELECT * FROM config.internal_flag
        WHERE name = 'serial.rematerialize_on_same_holding_code' AND enabled
    }, 1);
    return unless $flag_rv->{processed};
}


my $holding_code = (new JSON::XS)->decode($_TD->{new}{holding_code});

my $field = new MARC::Field('999', @$holding_code); # tag doesnt matter

my $dstmt = spi_prepare(
    'DELETE FROM serial.materialized_holding_code WHERE issuance = $1',
    'INT'
);
spi_exec_prepared($dstmt, $_TD->{new}{id});

my $istmt = spi_prepare(
    q{
        INSERT INTO serial.materialized_holding_code (
            issuance, subfield, value
        ) VALUES ($1, $2, $3)
    }, qw{INT CHAR TEXT}
);

foreach ($field->subfields) {
    spi_exec_prepared(
        $istmt,
        $_TD->{new}{id},
        $_->[0],
        $_->[1]
    );
}

return;

$func$ LANGUAGE 'plperlu';

CREATE INDEX assist_holdings_display
    ON serial.materialized_holding_code (issuance, subfield);

CREATE TRIGGER materialize_holding_code
    AFTER INSERT OR UPDATE ON serial.issuance
    FOR EACH ROW EXECUTE PROCEDURE serial.materialize_holding_code() ;

-- starting here, we materialize all existing holding codes.

UPDATE config.internal_flag
    SET enabled = TRUE
    WHERE name = 'serial.rematerialize_on_same_holding_code';

UPDATE serial.issuance SET holding_code = holding_code;

UPDATE config.internal_flag
    SET enabled = FALSE
    WHERE name = 'serial.rematerialize_on_same_holding_code';

-- finish holding code materialization process

-- fix up missing holding_code fields from serial.issuance
UPDATE serial.issuance siss
    SET holding_type = scap.type
    FROM serial.caption_and_pattern scap
    WHERE scap.id = siss.caption_and_pattern AND siss.holding_type IS NULL;


-- Evergreen DB patch 0701.schema.patron_stat_category_enhancements.sql
--
-- Enables users to set patron statistical categories as required,
-- whether or not users can input free text for the category value.
-- Enables administrators to set an entry as the default for any
-- given patron statistical category and org unit.
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0701', :eg_version);

-- New table

CREATE TABLE actor.stat_cat_entry_default (
    id              SERIAL  PRIMARY KEY,
    stat_cat_entry  INT     NOT NULL REFERENCES actor.stat_cat_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    stat_cat        INT     NOT NULL REFERENCES actor.stat_cat (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT sced_once_per_owner UNIQUE (stat_cat,owner)
);

COMMENT ON TABLE actor.stat_cat_entry_default IS $$
User Statistical Category Default Entry

A library may choose one of the stat_cat entries to be the
default entry.
$$;

-- Add columns to existing tables

-- Patron stat cat required column
ALTER TABLE actor.stat_cat
    ADD COLUMN required BOOL NOT NULL DEFAULT FALSE;

-- Patron stat cat allow_freetext column
ALTER TABLE actor.stat_cat
    ADD COLUMN allow_freetext BOOL NOT NULL DEFAULT TRUE;

-- Add permissions

INSERT INTO permission.perm_list ( id, code, description ) VALUES
    ( 525, 'CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT', oils_i18n_gettext( 525, 
        'User may set a default entry in a patron statistical category', 'ppl', 'description' )),
    ( 526, 'UPDATE_PATRON_STAT_CAT_ENTRY_DEFAULT', oils_i18n_gettext( 526, 
        'User may reset a default entry in a patron statistical category', 'ppl', 'description' )),
    ( 527, 'DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT', oils_i18n_gettext( 527, 
        'User may unset a default entry in a patron statistical category', 'ppl', 'description' ));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, TRUE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Circulation Administrator' AND
        aout.name = 'System' AND
        perm.code IN ('CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT', 'DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT');


SELECT evergreen.upgrade_deps_block_check('0702', :eg_version);

INSERT INTO config.global_flag (name, enabled, label) 
    VALUES (
        'opac.org_unit.non_inherited_visibility',
        FALSE,
        oils_i18n_gettext(
            'opac.org_unit.non_inherited_visibility',
            'Org Units Do Not Inherit Visibility',
            'cgf',
            'label'
        )
    );

CREATE TYPE actor.org_unit_custom_tree_purpose AS ENUM ('opac');

CREATE TABLE actor.org_unit_custom_tree (
    id              SERIAL  PRIMARY KEY,
    active          BOOLEAN DEFAULT FALSE,
    purpose         actor.org_unit_custom_tree_purpose NOT NULL DEFAULT 'opac' UNIQUE
);

CREATE TABLE actor.org_unit_custom_tree_node (
    id              SERIAL  PRIMARY KEY,
    tree            INTEGER REFERENCES actor.org_unit_custom_tree (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit        INTEGER NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	parent_node     INTEGER REFERENCES actor.org_unit_custom_tree_node (id) DEFERRABLE INITIALLY DEFERRED,
    sibling_order   INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT aouctn_once_per_org UNIQUE (tree, org_unit)
);
    

/* UNDO
BEGIN;
DELETE FROM config.global_flag WHERE name = 'opac.org_unit.non_inheritied_visibility';
DROP TABLE actor.org_unit_custom_tree_node;
DROP TABLE actor.org_unit_custom_tree;
DROP TYPE actor.org_unit_custom_tree_purpose;
COMMIT;
*/

-- Evergreen DB patch 0704.schema.query_parser_fts.sql
--
-- Add pref_ou query filter for preferred library searching
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0704', :eg_version);

-- Create the new 11-parameter function, featuring param_pref_ou
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
    staff           BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

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

        SELECT array_accum(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );

    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP
            SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT array_accum(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
        SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors(param_pref_ou);
        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

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
                AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
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
                    AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
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
                    AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
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
              WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                    AND record IN ( SELECT * FROM unnest( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                  WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
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
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  asset.call_number cn
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND NOT cp.deleted
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

-- Drop the old 10-parameter function
DROP FUNCTION IF EXISTS search.query_parser_fts (
    INT, INT, TEXT, INT[], INT[], INT, INT, INT, BOOL, BOOL
);

-- Evergreen DB patch 0705.data.custom-org-tree-perms.sql
--
-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0705', :eg_version);

INSERT INTO permission.perm_list (id, code, description)
    VALUES (
        528,
        'ADMIN_ORG_UNIT_CUSTOM_TREE',
        oils_i18n_gettext(
            528,
            'User may update custom org unit trees',
            'ppl',
            'description'
        )
    );

-- Evergreen DB patch 0707.schema.acq-vandelay-integration.sql

SELECT evergreen.upgrade_deps_block_check('0707', :eg_version);

-- seed data --

INSERT INTO permission.perm_list ( id, code, description )
    VALUES (
        529,
        'ADMIN_IMPORT_MATCH_SET',
        oils_i18n_gettext(
            529,
            'Allows a user to create/retrieve/update/delete vandelay match sets',
            'ppl',
            'description'
        )
    ), (
        530,
        'VIEW_IMPORT_MATCH_SET',
        oils_i18n_gettext(
            530,
            'Allows a user to view vandelay match sets',
            'ppl',
            'description'
        )
    );

-- This upgrade script fixed a typo in a previous one. It was corrected in the proper place in this file.
-- Still, record the fact it has been "applied".
SELECT evergreen.upgrade_deps_block_check('0708', :eg_version);

-- Evergreen DB patch 0709.data.misc_missing_perms.sql

SELECT evergreen.upgrade_deps_block_check('0709', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 
        531, 
        'ADMIN_ADDRESS_ALERT',
        oils_i18n_gettext( 
            531,
            'Allows a user to create/retrieve/update/delete address alerts',
            'ppl', 
            'description' 
        )
    ), ( 
        532, 
        'VIEW_ADDRESS_ALERT',
        oils_i18n_gettext( 
            532,
            'Allows a user to view address alerts',
            'ppl', 
            'description' 
        )
    ), ( 
        533, 
        'ADMIN_COPY_LOCATION_GROUP',
        oils_i18n_gettext( 
            533,
            'Allows a user to create/retrieve/update/delete copy location groups',
            'ppl', 
            'description' 
        )
    ), ( 
        534, 
        'ADMIN_USER_ACTIVITY_TYPE',
        oils_i18n_gettext( 
            534,
            'Allows a user to create/retrieve/update/delete user activity types',
            'ppl', 
            'description' 
        )
    );


-- Evergreen DB patch 0716.coded_value_map_id_seq_fix.sql

SELECT evergreen.upgrade_deps_block_check('0716', :eg_version);

SELECT SETVAL('config.coded_value_map_id_seq'::TEXT, (SELECT max(id) FROM config.coded_value_map));

COMMIT;

\qecho ************************************************************************
\qecho The following transaction, wrapping upgrade 0672, may take a while.  If
\qecho it takes an unduly long time, try it outside of a transaction.
\qecho ************************************************************************

BEGIN;

-- Evergreen DB patch 0672.fix-nonfiling-titles.sql
--
-- Titles that begin with non-filing articles using apostrophes
-- (for example, "L'armée") get spaces injected between the article
-- and the subsequent text, which then breaks searching for titles
-- beginning with those articles.
--
-- This patch adds a nonfiling title element to MODS32 that can then
-- be used to retrieve the title proper without affecting the spaces
-- in the title. It's what we want, what we really really want, for
-- title searches.
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0672', :eg_version);

-- Update the XPath definition before the titleNonfiling element exists;
-- but are you really going to read through the whole XSL below before
-- seeing this important bit?
UPDATE config.metabib_field
    SET xpath = $$//mods32:mods/mods32:titleNonfiling[mods32:title and not (@type)]$$,
        format = 'mods32'
    WHERE field_class = 'title' AND name = 'proper';

UPDATE config.xml_transform SET xslt=$$<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns="http://www.loc.gov/mods/v3" xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="xlink marc" version="1.0">
	<xsl:output encoding="UTF-8" indent="yes" method="xml"/>
<!--
Revision 1.14 - Fixed template isValid and fields 010, 020, 022, 024, 028, and 037 to output additional identifier elements 
  with corresponding @type and @invalid eq 'yes' when subfields z or y (in the case of 022) exist in the MARCXML ::: 2007/01/04 17:35:20 cred

Revision 1.13 - Changed order of output under cartographics to reflect schema  2006/11/28 tmee
	
Revision 1.12 - Updated to reflect MODS 3.2 Mapping  2006/10/11 tmee
		
Revision 1.11 - The attribute objectPart moved from <languageTerm> to <language>
      2006/04/08  jrad

Revision 1.10 MODS 3.1 revisions to language and classification elements  
				(plus ability to find marc:collection embedded in wrapper elements such as SRU zs: wrappers)
				2006/02/06  ggar

Revision 1.9 subfield $y was added to field 242 2004/09/02 10:57 jrad

Revision 1.8 Subject chopPunctuation expanded and attribute fixes 2004/08/12 jrad

Revision 1.7 2004/03/25 08:29 jrad

Revision 1.6 various validation fixes 2004/02/20 ntra

Revision 1.5  2003/10/02 16:18:58  ntra
MODS2 to MODS3 updates, language unstacking and 
de-duping, chopPunctuation expanded

Revision 1.3  2003/04/03 00:07:19  ntra
Revision 1.3 Additional Changes not related to MODS Version 2.0 by ntra

Revision 1.2  2003/03/24 19:37:42  ckeith
Added Log Comment

-->
	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="//marc:collection">
				<modsCollection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:collection/marc:record">
						<mods version="3.2">
							<xsl:call-template name="marcRecord"/>
						</mods>
					</xsl:for-each>
				</modsCollection>
			</xsl:when>
			<xsl:otherwise>
				<mods xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="3.2" xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-2.xsd">
					<xsl:for-each select="//marc:record">
						<xsl:call-template name="marcRecord"/>
					</xsl:for-each>
				</mods>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="marcRecord">
		<xsl:variable name="leader" select="marc:leader"/>
		<xsl:variable name="leader6" select="substring($leader,7,1)"/>
		<xsl:variable name="leader7" select="substring($leader,8,1)"/>
		<xsl:variable name="controlField008" select="marc:controlfield[@tag='008']"/>
		<xsl:variable name="typeOf008">
			<xsl:choose>
				<xsl:when test="$leader6='a'">
					<xsl:choose>
						<xsl:when test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'">BK</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'">SE</xsl:when>
					</xsl:choose>
				</xsl:when>
				<xsl:when test="$leader6='t'">BK</xsl:when>
				<xsl:when test="$leader6='p'">MM</xsl:when>
				<xsl:when test="$leader6='m'">CF</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">MP</xsl:when>
				<xsl:when test="$leader6='g' or $leader6='k' or $leader6='o' or $leader6='r'">VM</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d' or $leader6='i' or $leader6='j'">MU</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:for-each select="marc:datafield[@tag='245']">
			<titleInfo>
				<xsl:variable name="title">
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='b']">
							<xsl:call-template name="specialSubfieldSelect">
								<xsl:with-param name="axis">b</xsl:with-param>
								<xsl:with-param name="beforeCodes">afgk</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">abfgk</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<xsl:variable name="titleChop">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="$title"/>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:variable>
				<xsl:choose>
					<xsl:when test="@ind2>0">
						<nonSort>
							<xsl:value-of select="substring($titleChop,1,@ind2)"/>
						</nonSort>
						<title>
							<xsl:value-of select="substring($titleChop,@ind2+1)"/>
						</title>
					</xsl:when>
					<xsl:otherwise>
						<title>
							<xsl:value-of select="$titleChop"/>
						</title>
					</xsl:otherwise>
				</xsl:choose>
				<xsl:if test="marc:subfield[@code='b']">
					<subTitle>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="axis">b</xsl:with-param>
									<xsl:with-param name="anyCodes">b</xsl:with-param>
									<xsl:with-param name="afterCodes">afgk</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</subTitle>
				</xsl:if>
				<xsl:call-template name="part"></xsl:call-template>
			</titleInfo>
			<!-- A form of title that ignores non-filing characters; useful
				 for not converting "L'Oreal" into "L' Oreal" at index time -->
			<titleNonfiling>
				<xsl:variable name="title">
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='b']">
							<xsl:call-template name="specialSubfieldSelect">
								<xsl:with-param name="axis">b</xsl:with-param>
								<xsl:with-param name="beforeCodes">afgk</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">abfgk</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:variable>
				<title>
					<xsl:value-of select="$title"/>
				</title>
				<xsl:if test="marc:subfield[@code='b']">
					<subTitle>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="axis">b</xsl:with-param>
									<xsl:with-param name="anyCodes">b</xsl:with-param>
									<xsl:with-param name="afterCodes">afgk</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</subTitle>
				</xsl:if>
				<xsl:call-template name="part"></xsl:call-template>
			</titleNonfiling>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='210']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='242']">
			<titleInfo type="translated">
				<!--09/01/04 Added subfield $y-->
				<xsl:for-each select="marc:subfield[@code='y']">
					<xsl:attribute name="lang">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, b -->
								<xsl:with-param name="codes">a</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<!-- 1/04 fix -->
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='246']">
			<titleInfo type="alternative">
				<xsl:for-each select="marc:subfield[@code='i']">
					<xsl:attribute name="displayLabel">
						<xsl:value-of select="text()"/>
					</xsl:attribute>
				</xsl:for-each>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<!-- 1/04 removed $h, $b -->
								<xsl:with-param name="codes">af</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="subtitle"/>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='130']|marc:datafield[@tag='240']|marc:datafield[@tag='730'][@ind2!='2']">
			<titleInfo type="uniform">
				<title>
					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if test="(contains('adfklmor',@code) and (not(../marc:subfield[@code='n' or @code='p']) or (following-sibling::marc:subfield[@code='n' or @code='p'])))">
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
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='740'][@ind2!='2']">
			<titleInfo type="alternative">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ah</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:call-template name="part"/>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='100']">
			<name type="personal">
				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='110']">
			<name type="corporate">
				<xsl:call-template name="nameABCDN"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='111']">
			<name type="conference">
				<xsl:call-template name="nameACDEQ"/>
				<role>
					<roleTerm authority="marcrelator" type="text">creator</roleTerm>
				</role>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='700'][not(marc:subfield[@code='t'])]">
			<name type="personal">
				<xsl:call-template name="nameABCDQ"/>
				<xsl:call-template name="affiliation"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='710'][not(marc:subfield[@code='t'])]">
			<name type="corporate">
				<xsl:call-template name="nameABCDN"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='711'][not(marc:subfield[@code='t'])]">
			<name type="conference">
				<xsl:call-template name="nameACDEQ"/>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='720'][not(marc:subfield[@code='t'])]">
			<name>
				<xsl:if test="@ind1=1">
					<xsl:attribute name="type">
						<xsl:text>personal</xsl:text>
					</xsl:attribute>
				</xsl:if>
				<namePart>
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</namePart>
				<xsl:call-template name="role"/>
			</name>
		</xsl:for-each>
		<typeOfResource>
			<xsl:if test="$leader7='c'">
				<xsl:attribute name="collection">yes</xsl:attribute>
			</xsl:if>
			<xsl:if test="$leader6='d' or $leader6='f' or $leader6='p' or $leader6='t'">
				<xsl:attribute name="manuscript">yes</xsl:attribute>
			</xsl:if>
			<xsl:choose>
				<xsl:when test="$leader6='a' or $leader6='t'">text</xsl:when>
				<xsl:when test="$leader6='e' or $leader6='f'">cartographic</xsl:when>
				<xsl:when test="$leader6='c' or $leader6='d'">notated music</xsl:when>
				<xsl:when test="$leader6='i'">sound recording-nonmusical</xsl:when>
				<xsl:when test="$leader6='j'">sound recording-musical</xsl:when>
				<xsl:when test="$leader6='k'">still image</xsl:when>
				<xsl:when test="$leader6='g'">moving image</xsl:when>
				<xsl:when test="$leader6='r'">three dimensional object</xsl:when>
				<xsl:when test="$leader6='m'">software, multimedia</xsl:when>
				<xsl:when test="$leader6='p'">mixed material</xsl:when>
			</xsl:choose>
		</typeOfResource>
		<xsl:if test="substring($controlField008,26,1)='d'">
			<genre authority="marc">globe</genre>
		</xsl:if>
		<xsl:if test="marc:controlfield[@tag='007'][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
			<genre authority="marc">remote sensing image</genre>
		</xsl:if>
		<xsl:if test="$typeOf008='MP'">
			<xsl:variable name="controlField008-25" select="substring($controlField008,26,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-25='a' or $controlField008-25='b' or $controlField008-25='c' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
					<genre authority="marc">map</genre>
				</xsl:when>
				<xsl:when test="$controlField008-25='e' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
					<genre authority="marc">atlas</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='SE'">
			<xsl:variable name="controlField008-21" select="substring($controlField008,22,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-21='d'">
					<genre authority="marc">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='l'">
					<genre authority="marc">loose-leaf</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='m'">
					<genre authority="marc">series</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='n'">
					<genre authority="marc">newspaper</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='p'">
					<genre authority="marc">periodical</genre>
				</xsl:when>
				<xsl:when test="$controlField008-21='w'">
					<genre authority="marc">web site</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK' or $typeOf008='SE'">
			<xsl:variable name="controlField008-24" select="substring($controlField008,25,4)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="contains($controlField008-24,'a')">
					<genre authority="marc">abstract or summary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'b')">
					<genre authority="marc">bibliography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'c')">
					<genre authority="marc">catalog</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'d')">
					<genre authority="marc">dictionary</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'e')">
					<genre authority="marc">encyclopedia</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'f')">
					<genre authority="marc">handbook</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'g')">
					<genre authority="marc">legal article</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'i')">
					<genre authority="marc">index</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'k')">
					<genre authority="marc">discography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'l')">
					<genre authority="marc">legislation</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'m')">
					<genre authority="marc">theses</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'n')">
					<genre authority="marc">survey of literature</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'o')">
					<genre authority="marc">review</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'p')">
					<genre authority="marc">programmed text</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'q')">
					<genre authority="marc">filmography</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'r')">
					<genre authority="marc">directory</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'s')">
					<genre authority="marc">statistics</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'t')">
					<genre authority="marc">technical report</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'v')">
					<genre authority="marc">legal case and case notes</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'w')">
					<genre authority="marc">law report or digest</genre>
				</xsl:when>
				<xsl:when test="contains($controlField008-24,'z')">
					<genre authority="marc">treaty</genre>
				</xsl:when>
			</xsl:choose>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-29='1'">
					<genre authority="marc">conference publication</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='CF'">
			<xsl:variable name="controlField008-26" select="substring($controlField008,27,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-26='a'">
					<genre authority="marc">numeric data</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='e'">
					<genre authority="marc">database</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='f'">
					<genre authority="marc">font</genre>
				</xsl:when>
				<xsl:when test="$controlField008-26='g'">
					<genre authority="marc">game</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='BK'">
			<xsl:if test="substring($controlField008,25,1)='j'">
				<genre authority="marc">patent</genre>
			</xsl:if>
			<xsl:if test="substring($controlField008,31,1)='1'">
				<genre authority="marc">festschrift</genre>
			</xsl:if>
			<xsl:variable name="controlField008-34" select="substring($controlField008,35,1)"></xsl:variable>
			<xsl:if test="$controlField008-34='a' or $controlField008-34='b' or $controlField008-34='c' or $controlField008-34='d'">
				<genre authority="marc">biography</genre>
			</xsl:if>
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-33='e'">
					<genre authority="marc">essay</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marc">drama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marc">comic strip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marc">fiction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='h'">
					<genre authority="marc">humor, satire</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marc">letter</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marc">novel</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='j'">
					<genre authority="marc">short story</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marc">speech</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:if test="$typeOf008='MU'">
			<xsl:variable name="controlField008-30-31" select="substring($controlField008,31,2)"></xsl:variable>
			<xsl:if test="contains($controlField008-30-31,'b')">
				<genre authority="marc">biography</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'c')">
				<genre authority="marc">conference publication</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'d')">
				<genre authority="marc">drama</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'e')">
				<genre authority="marc">essay</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'f')">
				<genre authority="marc">fiction</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'o')">
				<genre authority="marc">folktale</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'h')">
				<genre authority="marc">history</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'k')">
				<genre authority="marc">humor, satire</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'m')">
				<genre authority="marc">memoir</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'p')">
				<genre authority="marc">poetry</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'r')">
				<genre authority="marc">rehearsal</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'g')">
				<genre authority="marc">reporting</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'s')">
				<genre authority="marc">sound</genre>
			</xsl:if>
			<xsl:if test="contains($controlField008-30-31,'l')">
				<genre authority="marc">speech</genre>
			</xsl:if>
		</xsl:if>
		<xsl:if test="$typeOf008='VM'">
			<xsl:variable name="controlField008-33" select="substring($controlField008,34,1)"></xsl:variable>
			<xsl:choose>
				<xsl:when test="$controlField008-33='a'">
					<genre authority="marc">art original</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='b'">
					<genre authority="marc">kit</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='c'">
					<genre authority="marc">art reproduction</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='d'">
					<genre authority="marc">diorama</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='f'">
					<genre authority="marc">filmstrip</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='g'">
					<genre authority="marc">legal article</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='i'">
					<genre authority="marc">picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='k'">
					<genre authority="marc">graphic</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='l'">
					<genre authority="marc">technical drawing</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='m'">
					<genre authority="marc">motion picture</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='n'">
					<genre authority="marc">chart</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='o'">
					<genre authority="marc">flash card</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='p'">
					<genre authority="marc">microscope slide</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='q' or marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
					<genre authority="marc">model</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='r'">
					<genre authority="marc">realia</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='s'">
					<genre authority="marc">slide</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='t'">
					<genre authority="marc">transparency</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='v'">
					<genre authority="marc">videorecording</genre>
				</xsl:when>
				<xsl:when test="$controlField008-33='w'">
					<genre authority="marc">toy</genre>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=655]">
			<genre authority="marc">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abvxyz</xsl:with-param>
					<xsl:with-param name="delimeter">-</xsl:with-param>
				</xsl:call-template>
			</genre>
		</xsl:for-each>
		<originInfo>
			<xsl:variable name="MARCpublicationCode" select="normalize-space(substring($controlField008,16,3))"></xsl:variable>
			<xsl:if test="translate($MARCpublicationCode,'|','')">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">marccountry</xsl:attribute>
						<xsl:value-of select="$MARCpublicationCode"/>
					</placeTerm>
				</place>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=044]/marc:subfield[@code='c']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">code</xsl:attribute>
						<xsl:attribute name="authority">iso3166</xsl:attribute>
						<xsl:value-of select="."/>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=260]/marc:subfield[@code='a']">
				<place>
					<placeTerm>
						<xsl:attribute name="type">text</xsl:attribute>
						<xsl:call-template name="chopPunctuationFront">
							<xsl:with-param name="chopString">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."/>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</placeTerm>
				</place>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='m']">
				<dateValid point="start">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='n']">
				<dateValid point="end">
					<xsl:value-of select="."/>
				</dateValid>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=046]/marc:subfield[@code='j']">
				<dateModified>
					<xsl:value-of select="."/>
				</dateModified>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=260]/marc:subfield[@code='b' or @code='c' or @code='g']">
				<xsl:choose>
					<xsl:when test="@code='b'">
						<publisher>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
								<xsl:with-param name="punctuation">
									<xsl:text>:,;/ </xsl:text>
								</xsl:with-param>
							</xsl:call-template>
						</publisher>
					</xsl:when>
					<xsl:when test="@code='c'">
						<dateIssued>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."/>
							</xsl:call-template>
						</dateIssued>
					</xsl:when>
					<xsl:when test="@code='g'">
						<dateCreated>
							<xsl:value-of select="."/>
						</dateCreated>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<xsl:variable name="dataField260c">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="marc:datafield[@tag=260]/marc:subfield[@code='c']"></xsl:with-param>
				</xsl:call-template>
			</xsl:variable>
			<xsl:variable name="controlField008-7-10" select="normalize-space(substring($controlField008, 8, 4))"></xsl:variable>
			<xsl:variable name="controlField008-11-14" select="normalize-space(substring($controlField008, 12, 4))"></xsl:variable>
			<xsl:variable name="controlField008-6" select="normalize-space(substring($controlField008, 7, 1))"></xsl:variable>
			<xsl:if test="$controlField008-6='e' or $controlField008-6='p' or $controlField008-6='r' or $controlField008-6='t' or $controlField008-6='s'">
				<xsl:if test="$controlField008-7-10 and ($controlField008-7-10 != $dataField260c)">
					<dateIssued encoding="marc">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='c' or $controlField008-6='d' or $controlField008-6='i' or $controlField008-6='k' or $controlField008-6='m' or $controlField008-6='q' or $controlField008-6='u'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-7-10">
					<dateIssued encoding="marc" point="start" qualifier="questionable">
						<xsl:value-of select="$controlField008-7-10"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='q'">
				<xsl:if test="$controlField008-11-14">
					<dateIssued encoding="marc" point="end" qualifier="questionable">
						<xsl:value-of select="$controlField008-11-14"/>
					</dateIssued>
				</xsl:if>
			</xsl:if>
			<xsl:if test="$controlField008-6='t'">
				<xsl:if test="$controlField008-11-14">
					<copyrightDate encoding="marc">
						<xsl:value-of select="$controlField008-11-14"/>
					</copyrightDate>
				</xsl:if>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=0 or @ind1=1]/marc:subfield[@code='a']">
				<dateCaptured encoding="iso8601">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][1]">
				<dateCaptured encoding="iso8601" point="start">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=033][@ind1=2]/marc:subfield[@code='a'][2]">
				<dateCaptured encoding="iso8601" point="end">
					<xsl:value-of select="."/>
				</dateCaptured>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=250]/marc:subfield[@code='a']">
				<edition>
					<xsl:value-of select="."/>
				</edition>
			</xsl:for-each>
			<xsl:for-each select="marc:leader">
				<issuance>
					<xsl:choose>
						<xsl:when test="$leader7='a' or $leader7='c' or $leader7='d' or $leader7='m'">monographic</xsl:when>
						<xsl:when test="$leader7='b' or $leader7='i' or $leader7='s'">continuing</xsl:when>
					</xsl:choose>
				</issuance>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=310]|marc:datafield[@tag=321]">
				<frequency>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">ab</xsl:with-param>
					</xsl:call-template>
				</frequency>
			</xsl:for-each>
		</originInfo>
		<xsl:variable name="controlField008-35-37" select="normalize-space(translate(substring($controlField008,36,3),'|#',''))"></xsl:variable>
		<xsl:if test="$controlField008-35-37">
			<language>
				<languageTerm authority="iso639-2b" type="code">
					<xsl:value-of select="substring($controlField008,36,3)"/>
				</languageTerm>
			</language>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=041]">
			<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='d' or @code='e' or @code='f' or @code='g' or @code='h']">
				<xsl:variable name="langCodes" select="."/>
				<xsl:choose>
					<xsl:when test="../marc:subfield[@code='2']='rfc3066'">
						<!-- not stacked but could be repeated -->
						<xsl:call-template name="rfcLanguages">
							<xsl:with-param name="nodeNum">
								<xsl:value-of select="1"/>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:text></xsl:text>
							</xsl:with-param>
							<xsl:with-param name="controlField008-35-37">
								<xsl:value-of select="$controlField008-35-37"></xsl:value-of>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:when>
					<xsl:otherwise>
						<!-- iso -->
						<xsl:variable name="allLanguages">
							<xsl:copy-of select="$langCodes"></xsl:copy-of>
						</xsl:variable>
						<xsl:variable name="currentLanguage">
							<xsl:value-of select="substring($allLanguages,1,3)"></xsl:value-of>
						</xsl:variable>
						<xsl:call-template name="isoLanguage">
							<xsl:with-param name="currentLanguage">
								<xsl:value-of select="substring($allLanguages,1,3)"></xsl:value-of>
							</xsl:with-param>
							<xsl:with-param name="remainingLanguages">
								<xsl:value-of select="substring($allLanguages,4,string-length($allLanguages)-3)"></xsl:value-of>
							</xsl:with-param>
							<xsl:with-param name="usedLanguages">
								<xsl:if test="$controlField008-35-37">
									<xsl:value-of select="$controlField008-35-37"></xsl:value-of>
								</xsl:if>
							</xsl:with-param>
						</xsl:call-template>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:variable name="physicalDescription">
			<!--3.2 change tmee 007/11 -->
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='a']">
				<digitalOrigin>reformatted digital</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='b']">
				<digitalOrigin>digitized microfilm</digitalOrigin>
			</xsl:if>
			<xsl:if test="$typeOf008='CF' and marc:controlfield[@tag=007][substring(.,12,1)='d']">
				<digitalOrigin>digitized other analog</digitalOrigin>
			</xsl:if>
			<xsl:variable name="controlField008-23" select="substring($controlField008,24,1)"></xsl:variable>
			<xsl:variable name="controlField008-29" select="substring($controlField008,30,1)"></xsl:variable>
			<xsl:variable name="check008-23">
				<xsl:if test="$typeOf008='BK' or $typeOf008='MU' or $typeOf008='SE' or $typeOf008='MM'">
					<xsl:value-of select="true()"></xsl:value-of>
				</xsl:if>
			</xsl:variable>
			<xsl:variable name="check008-29">
				<xsl:if test="$typeOf008='MP' or $typeOf008='VM'">
					<xsl:value-of select="true()"></xsl:value-of>
				</xsl:if>
			</xsl:variable>
			<xsl:choose>
				<xsl:when test="($check008-23 and $controlField008-23='f') or ($check008-29 and $controlField008-29='f')">
					<form authority="marcform">braille</form>
				</xsl:when>
				<xsl:when test="($controlField008-23=' ' and ($leader6='c' or $leader6='d')) or (($typeOf008='BK' or $typeOf008='SE') and ($controlField008-23=' ' or $controlField008='r'))">
					<form authority="marcform">print</form>
				</xsl:when>
				<xsl:when test="$leader6 = 'm' or ($check008-23 and $controlField008-23='s') or ($check008-29 and $controlField008-29='s')">
					<form authority="marcform">electronic</form>
				</xsl:when>
				<xsl:when test="($check008-23 and $controlField008-23='b') or ($check008-29 and $controlField008-29='b')">
					<form authority="marcform">microfiche</form>
				</xsl:when>
				<xsl:when test="($check008-23 and $controlField008-23='a') or ($check008-29 and $controlField008-29='a')">
					<form authority="marcform">microfilm</form>
				</xsl:when>
			</xsl:choose>
			<!-- 1/04 fix -->
			<xsl:if test="marc:datafield[@tag=130]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=130]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=240]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=240]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=242]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=242]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=245]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=245]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=246]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=246]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:if test="marc:datafield[@tag=730]/marc:subfield[@code='h']">
				<form authority="gmd">
					<xsl:call-template name="chopBrackets">
						<xsl:with-param name="chopString">
							<xsl:value-of select="marc:datafield[@tag=730]/marc:subfield[@code='h']"></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</form>
			</xsl:if>
			<xsl:for-each select="marc:datafield[@tag=256]/marc:subfield[@code='a']">
				<form>
					<xsl:value-of select="."></xsl:value-of>
				</form>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=007][substring(text(),1,1)='c']">
				<xsl:choose>
					<xsl:when test="substring(text(),14,1)='a'">
						<reformattingQuality>access</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='p'">
						<reformattingQuality>preservation</reformattingQuality>
					</xsl:when>
					<xsl:when test="substring(text(),14,1)='r'">
						<reformattingQuality>replacement</reformattingQuality>
					</xsl:when>
				</xsl:choose>
			</xsl:for-each>
			<!--3.2 change tmee 007/01 -->
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='b']">
				<form authority="smd">chip cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='c']">
				<form authority="smd">computer optical disc cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='j']">
				<form authority="smd">magnetic disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='m']">
				<form authority="smd">magneto-optical disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='o']">
				<form authority="smd">optical disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='r']">
				<form authority="smd">remote</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='a']">
				<form authority="smd">tape cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='f']">
				<form authority="smd">tape cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='c'][substring(text(),2,1)='h']">
				<form authority="smd">tape reel</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='a']">
				<form authority="smd">celestial globe</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='e']">
				<form authority="smd">earth moon globe</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='b']">
				<form authority="smd">planetary or lunar globe</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='d'][substring(text(),2,1)='c']">
				<form authority="smd">terrestrial globe</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='o'][substring(text(),2,1)='o']">
				<form authority="smd">kit</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='d']">
				<form authority="smd">atlas</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='g']">
				<form authority="smd">diagram</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='j']">
				<form authority="smd">map</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='q']">
				<form authority="smd">model</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='k']">
				<form authority="smd">profile</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='s']">
				<form authority="smd">section</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='a'][substring(text(),2,1)='y']">
				<form authority="smd">view</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='a']">
				<form authority="smd">aperture card</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='e']">
				<form authority="smd">microfiche</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='f']">
				<form authority="smd">microfiche cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='b']">
				<form authority="smd">microfilm cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='c']">
				<form authority="smd">microfilm cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='d']">
				<form authority="smd">microfilm reel</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='h'][substring(text(),2,1)='g']">
				<form authority="smd">microopaque</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='c']">
				<form authority="smd">film cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='f']">
				<form authority="smd">film cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='m'][substring(text(),2,1)='r']">
				<form authority="smd">film reel</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='n']">
				<form authority="smd">chart</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='c']">
				<form authority="smd">collage</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='d']">
				<form authority="smd">drawing</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='o']">
				<form authority="smd">flash card</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='e']">
				<form authority="smd">painting</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='f']">
				<form authority="smd">photomechanical print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='g']">
				<form authority="smd">photonegative</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='h']">
				<form authority="smd">photoprint</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='i']">
				<form authority="smd">picture</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='j']">
				<form authority="smd">print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='k'][substring(text(),2,1)='l']">
				<form authority="smd">technical drawing</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='q'][substring(text(),2,1)='q']">
				<form authority="smd">notated music</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='d']">
				<form authority="smd">filmslip</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='c']">
				<form authority="smd">filmstrip cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='o']">
				<form authority="smd">filmstrip roll</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='f']">
				<form authority="smd">other filmstrip type</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='s']">
				<form authority="smd">slide</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='g'][substring(text(),2,1)='t']">
				<form authority="smd">transparency</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='r'][substring(text(),2,1)='r']">
				<form authority="smd">remote-sensing image</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='e']">
				<form authority="smd">cylinder</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='q']">
				<form authority="smd">roll</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='g']">
				<form authority="smd">sound cartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='s']">
				<form authority="smd">sound cassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='d']">
				<form authority="smd">sound disc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='t']">
				<form authority="smd">sound-tape reel</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='i']">
				<form authority="smd">sound-track film</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='s'][substring(text(),2,1)='w']">
				<form authority="smd">wire recording</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='b']">
				<form authority="smd">combination</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='a']">
				<form authority="smd">moon</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='f'][substring(text(),2,1)='d']">
				<form authority="smd">tactile, with no writing system</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='c']">
				<form authority="smd">braille</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='b']">
				<form authority="smd">large print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='a']">
				<form authority="smd">regular print</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='t'][substring(text(),2,1)='d']">
				<form authority="smd">text in looseleaf binder</form>
			</xsl:if>
			
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='c']">
				<form authority="smd">videocartridge</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='f']">
				<form authority="smd">videocassette</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='d']">
				<form authority="smd">videodisc</form>
			</xsl:if>
			<xsl:if test="marc:controlfield[@tag=007][substring(text(),1,1)='v'][substring(text(),2,1)='r']">
				<form authority="smd">videoreel</form>
			</xsl:if>
			
			<xsl:for-each select="marc:datafield[@tag=856]/marc:subfield[@code='q'][string-length(.)>1]">
				<internetMediaType>
					<xsl:value-of select="."></xsl:value-of>
				</internetMediaType>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=300]">
				<extent>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abce</xsl:with-param>
					</xsl:call-template>
				</extent>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($physicalDescription))">
			<physicalDescription>
				<xsl:copy-of select="$physicalDescription"></xsl:copy-of>
			</physicalDescription>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=520]">
			<abstract>
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</abstract>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=505]">
			<tableOfContents>
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">agrt</xsl:with-param>
				</xsl:call-template>
			</tableOfContents>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=521]">
			<targetAudience>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</targetAudience>
		</xsl:for-each>
		<xsl:if test="$typeOf008='BK' or $typeOf008='CF' or $typeOf008='MU' or $typeOf008='VM'">
			<xsl:variable name="controlField008-22" select="substring($controlField008,23,1)"></xsl:variable>
			<xsl:choose>
				<!-- 01/04 fix -->
				<xsl:when test="$controlField008-22='d'">
					<targetAudience authority="marctarget">adolescent</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='e'">
					<targetAudience authority="marctarget">adult</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='g'">
					<targetAudience authority="marctarget">general</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='b' or $controlField008-22='c' or $controlField008-22='j'">
					<targetAudience authority="marctarget">juvenile</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='a'">
					<targetAudience authority="marctarget">preschool</targetAudience>
				</xsl:when>
				<xsl:when test="$controlField008-22='f'">
					<targetAudience authority="marctarget">specialized</targetAudience>
				</xsl:when>
			</xsl:choose>
		</xsl:if>
		<xsl:for-each select="marc:datafield[@tag=245]/marc:subfield[@code='c']">
			<note type="statement of responsibility">
				<xsl:value-of select="."></xsl:value-of>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=500]">
			<note>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
				<xsl:call-template name="uri"></xsl:call-template>
			</note>
		</xsl:for-each>
		
		<!--3.2 change tmee additional note fields-->
		
		<xsl:for-each select="marc:datafield[@tag=506]">
			<note type="restrictions">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=510]">
			<note  type="citation/reference">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
			
		<xsl:for-each select="marc:datafield[@tag=511]">
			<note type="performers">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=518]">
			<note type="venue">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=530]">
			<note  type="additional physical form">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=533]">
			<note  type="reproduction">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=534]">
			<note  type="original version">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=538]">
			<note  type="system details">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=583]">
			<note type="action">
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		

		
		
		
		<xsl:for-each select="marc:datafield[@tag=501 or @tag=502 or @tag=504 or @tag=507 or @tag=508 or  @tag=513 or @tag=514 or @tag=515 or @tag=516 or @tag=522 or @tag=524 or @tag=525 or @tag=526 or @tag=535 or @tag=536 or @tag=540 or @tag=541 or @tag=544 or @tag=545 or @tag=546 or @tag=547 or @tag=550 or @tag=552 or @tag=555 or @tag=556 or @tag=561 or @tag=562 or @tag=565 or @tag=567 or @tag=580 or @tag=581 or @tag=584 or @tag=585 or @tag=586]">
			<note>
				<xsl:call-template name="uri"></xsl:call-template>
				<xsl:variable name="str">
					<xsl:for-each select="marc:subfield[@code!='6' or @code!='8']">
						<xsl:value-of select="."></xsl:value-of>
						<xsl:text> </xsl:text>
					</xsl:for-each>
				</xsl:variable>
				<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
			</note>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=034][marc:subfield[@code='d' or @code='e' or @code='f' or @code='g']]">
			<subject>
				<cartographics>
					<coordinates>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">defg</xsl:with-param>
						</xsl:call-template>
					</coordinates>
				</cartographics>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=043]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
					<geographicCode>
						<xsl:attribute name="authority">
							<xsl:if test="@code='a'">
								<xsl:text>marcgac</xsl:text>
							</xsl:if>
							<xsl:if test="@code='b'">
								<xsl:value-of select="following-sibling::marc:subfield[@code=2]"></xsl:value-of>
							</xsl:if>
							<xsl:if test="@code='c'">
								<xsl:text>iso3166</xsl:text>
							</xsl:if>
						</xsl:attribute>
						<xsl:value-of select="self::marc:subfield"></xsl:value-of>
					</geographicCode>
				</xsl:for-each>
			</subject>
		</xsl:for-each>
		<!-- tmee 2006/11/27 -->
		<xsl:for-each select="marc:datafield[@tag=255]">
			<subject>
				<xsl:for-each select="marc:subfield[@code='a' or @code='b' or @code='c']">
				<cartographics>
					<xsl:if test="@code='a'">
						<scale>
							<xsl:value-of select="."></xsl:value-of>
						</scale>
					</xsl:if>
					<xsl:if test="@code='b'">
						<projection>
							<xsl:value-of select="."></xsl:value-of>
						</projection>
					</xsl:if>
					<xsl:if test="@code='c'">
						<coordinates>
							<xsl:value-of select="."></xsl:value-of>
						</coordinates>
					</xsl:if>
				</cartographics>
				</xsl:for-each>
			</subject>
		</xsl:for-each>
				
		<xsl:apply-templates select="marc:datafield[653 >= @tag and @tag >= 600]"></xsl:apply-templates>
		<xsl:apply-templates select="marc:datafield[@tag=656]"></xsl:apply-templates>
		<xsl:for-each select="marc:datafield[@tag=752]">
			<subject>
				<hierarchicalGeographic>
					<xsl:for-each select="marc:subfield[@code='a']">
						<country>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</country>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<state>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</state>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='c']">
						<county>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</county>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='d']">
						<city>
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString" select="."></xsl:with-param>
							</xsl:call-template>
						</city>
					</xsl:for-each>
				</hierarchicalGeographic>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=045][marc:subfield[@code='b']]">
			<subject>
				<xsl:choose>
					<xsl:when test="@ind1=2">
						<temporal encoding="iso8601" point="start">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][1]"></xsl:value-of>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
						<temporal encoding="iso8601" point="end">
							<xsl:call-template name="chopPunctuation">
								<xsl:with-param name="chopString">
									<xsl:value-of select="marc:subfield[@code='b'][2]"></xsl:value-of>
								</xsl:with-param>
							</xsl:call-template>
						</temporal>
					</xsl:when>
					<xsl:otherwise>
						<xsl:for-each select="marc:subfield[@code='b']">
							<temporal encoding="iso8601">
								<xsl:call-template name="chopPunctuation">
									<xsl:with-param name="chopString" select="."></xsl:with-param>
								</xsl:call-template>
							</temporal>
						</xsl:for-each>
					</xsl:otherwise>
				</xsl:choose>
			</subject>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=050]">
			<xsl:for-each select="marc:subfield[@code='b']">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"></xsl:value-of>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="preceding-sibling::marc:subfield[@code='a'][1]"></xsl:value-of>
					<xsl:text> </xsl:text>
					<xsl:value-of select="text()"></xsl:value-of>
				</classification>
			</xsl:for-each>
			<xsl:for-each select="marc:subfield[@code='a'][not(following-sibling::marc:subfield[@code='b'])]">
				<classification authority="lcc">
					<xsl:if test="../marc:subfield[@code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:value-of select="../marc:subfield[@code='3']"></xsl:value-of>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="text()"></xsl:value-of>
				</classification>
			</xsl:for-each>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=082]">
			<classification authority="ddc">
				<xsl:if test="marc:subfield[@code='2']">
					<xsl:attribute name="edition">
						<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
					</xsl:attribute>
				</xsl:if>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=080]">
			<classification authority="udc">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abx</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=060]">
			<classification authority="nlm">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=0]">
			<classification authority="sudocs">
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086][@ind1=1]">
			<classification authority="candoc">
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=086]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
				</xsl:attribute>
				<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=084]">
			<classification>
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
				</xsl:attribute>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</classification>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=440]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=490][@ind1=0]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">av</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=510]">
			<relatedItem type="isReferencedBy">
				<note>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcx3</xsl:with-param>
					</xsl:call-template>
				</note>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=534]">
			<relatedItem type="original">
				<xsl:call-template name="relatedTitle"></xsl:call-template>
				<xsl:call-template name="relatedName"></xsl:call-template>
				<xsl:if test="marc:subfield[@code='b' or @code='c']">
					<originInfo>
						<xsl:for-each select="marc:subfield[@code='c']">
							<publisher>
								<xsl:value-of select="."></xsl:value-of>
							</publisher>
						</xsl:for-each>
						<xsl:for-each select="marc:subfield[@code='b']">
							<edition>
								<xsl:value-of select="."></xsl:value-of>
							</edition>
						</xsl:for-each>
					</originInfo>
				</xsl:if>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
				<xsl:for-each select="marc:subfield[@code='z']">
					<identifier type="isbn">
						<xsl:value-of select="."></xsl:value-of>
					</identifier>
				</xsl:for-each>
				<xsl:call-template name="relatedNote"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=700][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aq</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">g</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"></xsl:call-template>
					<xsl:call-template name="nameDate"></xsl:call-template>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=710][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<xsl:variable name="tempNamePart">
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</xsl:variable>
					<xsl:if test="normalize-space($tempNamePart)">
						<namePart>
							<xsl:value-of select="$tempNamePart"></xsl:value-of>
						</namePart>
					</xsl:if>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=711][marc:subfield[@code='t']]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=730][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<xsl:call-template name="relatedForm"></xsl:call-template>
				<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=740][@ind2=2]">
			<relatedItem>
				<xsl:call-template name="constituentOrRelatedType"></xsl:call-template>
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<xsl:call-template name="relatedForm"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=760]|marc:datafield[@tag=762]">
			<relatedItem type="series">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=765]|marc:datafield[@tag=767]|marc:datafield[@tag=777]|marc:datafield[@tag=787]">
			<relatedItem>
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=775]">
			<relatedItem type="otherVersion">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=770]|marc:datafield[@tag=774]">
			<relatedItem type="constituent">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=772]|marc:datafield[@tag=773]">
			<relatedItem type="host">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=776]">
			<relatedItem type="otherFormat">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=780]">
			<relatedItem type="preceding">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=785]">
			<relatedItem type="succeeding">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=786]">
			<relatedItem type="original">
				<xsl:call-template name="relatedItem76X-78X"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=800]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"></xsl:call-template>
				</titleInfo>
				<name type="personal">
					<namePart>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">aq</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="beforeCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="termsOfAddress"></xsl:call-template>
					<xsl:call-template name="nameDate"></xsl:call-template>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=810]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklmorsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">dg</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</titleInfo>
				<name type="corporate">
					<xsl:for-each select="marc:subfield[@code='a']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<xsl:for-each select="marc:subfield[@code='b']">
						<namePart>
							<xsl:value-of select="."></xsl:value-of>
						</namePart>
					</xsl:for-each>
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">c</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">dgn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"></xsl:call-template>
				</name>
				<xsl:call-template name="relatedForm"></xsl:call-template>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=811]">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="specialSubfieldSelect">
									<xsl:with-param name="anyCodes">tfklsv</xsl:with-param>
									<xsl:with-param name="axis">t</xsl:with-param>
									<xsl:with-param name="afterCodes">g</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="relatedPartNumName"/>
				</titleInfo>
				<name type="conference">
					<namePart>
						<xsl:call-template name="specialSubfieldSelect">
							<xsl:with-param name="anyCodes">aqdc</xsl:with-param>
							<xsl:with-param name="axis">t</xsl:with-param>
							<xsl:with-param name="beforeCodes">gn</xsl:with-param>
						</xsl:call-template>
					</namePart>
					<xsl:call-template name="role"/>
				</name>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='830']">
			<relatedItem type="series">
				<titleInfo>
					<title>
						<xsl:call-template name="chopPunctuation">
							<xsl:with-param name="chopString">
								<xsl:call-template name="subfieldSelect">
									<xsl:with-param name="codes">adfgklmorsv</xsl:with-param>
								</xsl:call-template>
							</xsl:with-param>
						</xsl:call-template>
					</title>
					<xsl:call-template name="part"/>
				</titleInfo>
				<xsl:call-template name="relatedForm"/>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][@ind2='2']/marc:subfield[@code='q']">
			<relatedItem>
				<internetMediaType>
					<xsl:value-of select="."/>
				</internetMediaType>
			</relatedItem>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='020']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isbn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isbn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='0']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">isrc</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="isrc">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='2']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">ismn</xsl:with-param>
			</xsl:call-template>
			<xsl:if test="marc:subfield[@code='a']">
				<identifier type="ismn">
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='024'][@ind1='4']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">sici</xsl:with-param>
			</xsl:call-template>
			<identifier type="sici">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='022']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">issn</xsl:with-param>
			</xsl:call-template>
			<identifier type="issn">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='010']">
			<xsl:call-template name="isInvalid">
				<xsl:with-param name="type">lccn</xsl:with-param>
			</xsl:call-template>
			<identifier type="lccn">
				<xsl:value-of select="normalize-space(marc:subfield[@code='a'])"/>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='028']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when test="@ind1='0'">issue number</xsl:when>
						<xsl:when test="@ind1='1'">matrix number</xsl:when>
						<xsl:when test="@ind1='2'">music plate</xsl:when>
						<xsl:when test="@ind1='3'">music publisher</xsl:when>
						<xsl:when test="@ind1='4'">videorecording identifier</xsl:when>
					</xsl:choose>
				</xsl:attribute>
				<!--<xsl:call-template name="isInvalid"/>--> <!-- no $z in 028 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">
						<xsl:choose>
							<xsl:when test="@ind1='0'">ba</xsl:when>
							<xsl:otherwise>ab</xsl:otherwise>
						</xsl:choose>
					</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='037']">
			<identifier type="stock number">
				<!--<xsl:call-template name="isInvalid"/>--> <!-- no $z in 037 -->
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</identifier>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag='856'][marc:subfield[@code='u']]">
			<identifier>
				<xsl:attribute name="type">
					<xsl:choose>
						<xsl:when test="starts-with(marc:subfield[@code='u'],'urn:doi') or starts-with(marc:subfield[@code='u'],'doi')">doi</xsl:when>
						<xsl:when test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov')">hdl</xsl:when>
						<xsl:otherwise>uri</xsl:otherwise>
					</xsl:choose>
				</xsl:attribute>
				<xsl:choose>
					<xsl:when test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl') or starts-with(marc:subfield[@code='u'],'http://hdl.loc.gov') ">
						<xsl:value-of select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"></xsl:value-of>
					</xsl:when>
					<xsl:otherwise>
						<xsl:value-of select="marc:subfield[@code='u']"></xsl:value-of>
					</xsl:otherwise>
				</xsl:choose>
			</identifier>
			<xsl:if test="starts-with(marc:subfield[@code='u'],'urn:hdl') or starts-with(marc:subfield[@code='u'],'hdl')">
				<identifier type="hdl">
					<xsl:if test="marc:subfield[@code='y' or @code='3' or @code='z']">
						<xsl:attribute name="displayLabel">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">y3z</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="concat('hdl:',substring-after(marc:subfield[@code='u'],'http://hdl.loc.gov/'))"></xsl:value-of>
				</identifier>
			</xsl:if>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=024][@ind1=1]">
			<identifier type="upc">
				<xsl:call-template name="isInvalid"/>
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</identifier>
		</xsl:for-each>
		<!-- 1/04 fix added $y -->
		<xsl:for-each select="marc:datafield[@tag=856][marc:subfield[@code='u']]">
			<location>
				<url>
					<xsl:if test="marc:subfield[@code='y' or @code='3']">
						<xsl:attribute name="displayLabel">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">y3</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:if test="marc:subfield[@code='z' ]">
						<xsl:attribute name="note">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">z</xsl:with-param>
							</xsl:call-template>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="marc:subfield[@code='u']"></xsl:value-of>

				</url>
			</location>
		</xsl:for-each>
			
			<!-- 3.2 change tmee 856z  -->

		
		<xsl:for-each select="marc:datafield[@tag=852]">
			<location>
				<physicalLocation>
					<xsl:call-template name="displayLabel"></xsl:call-template>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abje</xsl:with-param>
					</xsl:call-template>
				</physicalLocation>
			</location>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=506]">
			<accessCondition type="restrictionOnAccess">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcd35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=540]">
			<accessCondition type="useAndReproduction">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">abcde35</xsl:with-param>
				</xsl:call-template>
			</accessCondition>
		</xsl:for-each>
		<recordInfo>
			<xsl:for-each select="marc:datafield[@tag=040]">
				<recordContentSource authority="marcorg">
					<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
				</recordContentSource>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=008]">
				<recordCreationDate encoding="marc">
					<xsl:value-of select="substring(.,1,6)"></xsl:value-of>
				</recordCreationDate>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=005]">
				<recordChangeDate encoding="iso8601">
					<xsl:value-of select="."></xsl:value-of>
				</recordChangeDate>
			</xsl:for-each>
			<xsl:for-each select="marc:controlfield[@tag=001]">
				<recordIdentifier>
					<xsl:if test="../marc:controlfield[@tag=003]">
						<xsl:attribute name="source">
							<xsl:value-of select="../marc:controlfield[@tag=003]"></xsl:value-of>
						</xsl:attribute>
					</xsl:if>
					<xsl:value-of select="."></xsl:value-of>
				</recordIdentifier>
			</xsl:for-each>
			<xsl:for-each select="marc:datafield[@tag=040]/marc:subfield[@code='b']">
				<languageOfCataloging>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="."></xsl:value-of>
					</languageTerm>
				</languageOfCataloging>
			</xsl:for-each>
		</recordInfo>
	</xsl:template>
	<xsl:template name="displayForm">
		<xsl:for-each select="marc:subfield[@code='c']">
			<displayForm>
				<xsl:value-of select="."></xsl:value-of>
			</displayForm>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="affiliation">
		<xsl:for-each select="marc:subfield[@code='u']">
			<affiliation>
				<xsl:value-of select="."></xsl:value-of>
			</affiliation>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="uri">
		<xsl:for-each select="marc:subfield[@code='u']">
			<xsl:attribute name="xlink:href">
				<xsl:value-of select="."></xsl:value-of>
			</xsl:attribute>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="role">
		<xsl:for-each select="marc:subfield[@code='e']">
			<role>
				<roleTerm type="text">
					<xsl:value-of select="."></xsl:value-of>
				</roleTerm>
			</role>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='4']">
			<role>
				<roleTerm authority="marcrelator" type="code">
					<xsl:value-of select="."></xsl:value-of>
				</roleTerm>
			</role>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="part">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">n</xsl:with-param>
				<xsl:with-param name="anyCodes">n</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partNumber"></xsl:with-param>
				</xsl:call-template>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partName"></xsl:with-param>
				</xsl:call-template>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPart">
		<xsl:if test="@tag=773">
			<xsl:for-each select="marc:subfield[@code='g']">
				<part>
					<text>
						<xsl:value-of select="."></xsl:value-of>
					</text>
				</part>
			</xsl:for-each>
			<xsl:for-each select="marc:subfield[@code='q']">
				<part>
					<xsl:call-template name="parsePart"></xsl:call-template>
				</part>
			</xsl:for-each>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedPartNumName">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">g</xsl:with-param>
				<xsl:with-param name="anyCodes">g</xsl:with-param>
				<xsl:with-param name="afterCodes">pst</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fgkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<partNumber>
				<xsl:value-of select="$partNumber"></xsl:value-of>
			</partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<partName>
				<xsl:value-of select="$partName"></xsl:value-of>
			</partName>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedName">
		<xsl:for-each select="marc:subfield[@code='a']">
			<name>
				<namePart>
					<xsl:value-of select="."></xsl:value-of>
				</namePart>
			</name>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedForm">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<form>
					<xsl:value-of select="."></xsl:value-of>
				</form>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedExtent">
		<xsl:for-each select="marc:subfield[@code='h']">
			<physicalDescription>
				<extent>
					<xsl:value-of select="."></xsl:value-of>
				</extent>
			</physicalDescription>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedNote">
		<xsl:for-each select="marc:subfield[@code='n']">
			<note>
				<xsl:value-of select="."></xsl:value-of>
			</note>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedSubject">
		<xsl:for-each select="marc:subfield[@code='j']">
			<subject>
				<temporal encoding="iso8601">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."></xsl:with-param>
					</xsl:call-template>
				</temporal>
			</subject>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierISSN">
		<xsl:for-each select="marc:subfield[@code='x']">
			<identifier type="issn">
				<xsl:value-of select="."></xsl:value-of>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifierLocal">
		<xsl:for-each select="marc:subfield[@code='w']">
			<identifier type="local">
				<xsl:value-of select="."></xsl:value-of>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedIdentifier">
		<xsl:for-each select="marc:subfield[@code='o']">
			<identifier>
				<xsl:value-of select="."></xsl:value-of>
			</identifier>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedItem76X-78X">
		<xsl:call-template name="displayLabel"></xsl:call-template>
		<xsl:call-template name="relatedTitle76X-78X"></xsl:call-template>
		<xsl:call-template name="relatedName"></xsl:call-template>
		<xsl:call-template name="relatedOriginInfo"></xsl:call-template>
		<xsl:call-template name="relatedLanguage"></xsl:call-template>
		<xsl:call-template name="relatedExtent"></xsl:call-template>
		<xsl:call-template name="relatedNote"></xsl:call-template>
		<xsl:call-template name="relatedSubject"></xsl:call-template>
		<xsl:call-template name="relatedIdentifier"></xsl:call-template>
		<xsl:call-template name="relatedIdentifierISSN"></xsl:call-template>
		<xsl:call-template name="relatedIdentifierLocal"></xsl:call-template>
		<xsl:call-template name="relatedPart"></xsl:call-template>
	</xsl:template>
	<xsl:template name="subjectGeographicZ">
		<geographic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</geographic>
	</xsl:template>
	<xsl:template name="subjectTemporalY">
		<temporal>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</temporal>
	</xsl:template>
	<xsl:template name="subjectTopic">
		<topic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</topic>
	</xsl:template>	
	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template name="subjectGenre">
		<genre>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="."></xsl:with-param>
			</xsl:call-template>
		</genre>
	</xsl:template>
	
	<xsl:template name="nameABCDN">
		<xsl:for-each select="marc:subfield[@code='a']">
			<namePart>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."></xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='b']">
			<namePart>
				<xsl:value-of select="."></xsl:value-of>
			</namePart>
		</xsl:for-each>
		<xsl:if test="marc:subfield[@code='c'] or marc:subfield[@code='d'] or marc:subfield[@code='n']">
			<namePart>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">cdn</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="nameABCDQ">
		<namePart>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">aq</xsl:with-param>
					</xsl:call-template>
				</xsl:with-param>
				<xsl:with-param name="punctuation">
					<xsl:text>:,;/ </xsl:text>
				</xsl:with-param>
			</xsl:call-template>
		</namePart>
		<xsl:call-template name="termsOfAddress"></xsl:call-template>
		<xsl:call-template name="nameDate"></xsl:call-template>
	</xsl:template>
	<xsl:template name="nameACDEQ">
		<namePart>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">acdeq</xsl:with-param>
			</xsl:call-template>
		</namePart>
	</xsl:template>
	<xsl:template name="constituentOrRelatedType">
		<xsl:if test="@ind2=2">
			<xsl:attribute name="type">constituent</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedTitle">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedTitle76X-78X">
		<xsl:for-each select="marc:subfield[@code='t']">
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='p']">
			<titleInfo type="abbreviated">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='s']">
			<titleInfo type="uniform">
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="."></xsl:value-of>
						</xsl:with-param>
					</xsl:call-template>
				</title>
				<xsl:if test="marc:datafield[@tag!=773]and marc:subfield[@code='g']">
					<xsl:call-template name="relatedPartNumName"></xsl:call-template>
				</xsl:if>
			</titleInfo>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="relatedOriginInfo">
		<xsl:if test="marc:subfield[@code='b' or @code='d'] or marc:subfield[@code='f']">
			<originInfo>
				<xsl:if test="@tag=775">
					<xsl:for-each select="marc:subfield[@code='f']">
						<place>
							<placeTerm>
								<xsl:attribute name="type">code</xsl:attribute>
								<xsl:attribute name="authority">marcgac</xsl:attribute>
								<xsl:value-of select="."></xsl:value-of>
							</placeTerm>
						</place>
					</xsl:for-each>
				</xsl:if>
				<xsl:for-each select="marc:subfield[@code='d']">
					<publisher>
						<xsl:value-of select="."></xsl:value-of>
					</publisher>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<edition>
						<xsl:value-of select="."></xsl:value-of>
					</edition>
				</xsl:for-each>
			</originInfo>
		</xsl:if>
	</xsl:template>
	<xsl:template name="relatedLanguage">
		<xsl:for-each select="marc:subfield[@code='e']">
			<xsl:call-template name="getLanguage">
				<xsl:with-param name="langString">
					<xsl:value-of select="."></xsl:value-of>
				</xsl:with-param>
			</xsl:call-template>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="nameDate">
		<xsl:for-each select="marc:subfield[@code='d']">
			<namePart type="date">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."></xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="subjectAuthority">
		<xsl:if test="@ind2!=4">
			<xsl:if test="@ind2!=' '">
				<xsl:if test="@ind2!=8">
					<xsl:if test="@ind2!=9">
						<xsl:attribute name="authority">
							<xsl:choose>
								<xsl:when test="@ind2=0">lcsh</xsl:when>
								<xsl:when test="@ind2=1">lcshac</xsl:when>
								<xsl:when test="@ind2=2">mesh</xsl:when>
								<!-- 1/04 fix -->
								<xsl:when test="@ind2=3">nal</xsl:when>
								<xsl:when test="@ind2=5">csh</xsl:when>
								<xsl:when test="@ind2=6">rvm</xsl:when>
								<xsl:when test="@ind2=7">
									<xsl:value-of select="marc:subfield[@code='2']"></xsl:value-of>
								</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
				</xsl:if>
			</xsl:if>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subjectAnyOrder">
		<xsl:for-each select="marc:subfield[@code='v' or @code='x' or @code='y' or @code='z']">
			<xsl:choose>
				<xsl:when test="@code='v'">
					<xsl:call-template name="subjectGenre"></xsl:call-template>
				</xsl:when>
				<xsl:when test="@code='x'">
					<xsl:call-template name="subjectTopic"></xsl:call-template>
				</xsl:when>
				<xsl:when test="@code='y'">
					<xsl:call-template name="subjectTemporalY"></xsl:call-template>
				</xsl:when>
				<xsl:when test="@code='z'">
					<xsl:call-template name="subjectGeographicZ"></xsl:call-template>
				</xsl:when>
			</xsl:choose>
		</xsl:for-each>
	</xsl:template>
	<xsl:template name="specialSubfieldSelect">
		<xsl:param name="anyCodes"></xsl:param>
		<xsl:param name="axis"></xsl:param>
		<xsl:param name="beforeCodes"></xsl:param>
		<xsl:param name="afterCodes"></xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($anyCodes, @code)      or (contains($beforeCodes,@code) and following-sibling::marc:subfield[@code=$axis])      or (contains($afterCodes,@code) and preceding-sibling::marc:subfield[@code=$axis])">
					<xsl:value-of select="text()"></xsl:value-of>
					<xsl:text> </xsl:text>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-1)"></xsl:value-of>
	</xsl:template>
	
	<!-- 3.2 change tmee 6xx $v genre -->
	<xsl:template match="marc:datafield[@tag=600]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<name type="personal">
				<xsl:call-template name="termsOfAddress"></xsl:call-template>
				<namePart>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">aq</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:call-template name="nameDate"></xsl:call-template>
				<xsl:call-template name="affiliation"></xsl:call-template>
				<xsl:call-template name="role"></xsl:call-template>
			</name>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=610]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<name type="corporate">
				<xsl:for-each select="marc:subfield[@code='a']">
					<namePart>
						<xsl:value-of select="."></xsl:value-of>
					</namePart>
				</xsl:for-each>
				<xsl:for-each select="marc:subfield[@code='b']">
					<namePart>
						<xsl:value-of select="."></xsl:value-of>
					</namePart>
				</xsl:for-each>
				<xsl:if test="marc:subfield[@code='c' or @code='d' or @code='n' or @code='p']">
					<namePart>
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">cdnp</xsl:with-param>
						</xsl:call-template>
					</namePart>
				</xsl:if>
				<xsl:call-template name="role"></xsl:call-template>
			</name>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=611]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<name type="conference">
				<namePart>
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">abcdeqnp</xsl:with-param>
					</xsl:call-template>
				</namePart>
				<xsl:for-each select="marc:subfield[@code='4']">
					<role>
						<roleTerm authority="marcrelator" type="code">
							<xsl:value-of select="."></xsl:value-of>
						</roleTerm>
					</role>
				</xsl:for-each>
			</name>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=630]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<titleInfo>
				<title>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">adfhklor</xsl:with-param>
							</xsl:call-template>
						</xsl:with-param>
					</xsl:call-template>
					<xsl:call-template name="part"></xsl:call-template>
				</title>
			</titleInfo>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=650]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<topic>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">abcd</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</topic>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=651]">
		<subject>
			<xsl:call-template name="subjectAuthority"></xsl:call-template>
			<xsl:for-each select="marc:subfield[@code='a']">
				<geographic>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString" select="."></xsl:with-param>
					</xsl:call-template>
				</geographic>
			</xsl:for-each>
			<xsl:call-template name="subjectAnyOrder"></xsl:call-template>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=653]">
		<subject>
			<xsl:for-each select="marc:subfield[@code='a']">
				<topic>
					<xsl:value-of select="."></xsl:value-of>
				</topic>
			</xsl:for-each>
		</subject>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=656]">
		<subject>
			<xsl:if test="marc:subfield[@code=2]">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code=2]"></xsl:value-of>
				</xsl:attribute>
			</xsl:if>
			<occupation>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='a']"></xsl:value-of>
					</xsl:with-param>
				</xsl:call-template>
			</occupation>
		</subject>
	</xsl:template>
	<xsl:template name="termsOfAddress">
		<xsl:if test="marc:subfield[@code='b' or @code='c']">
			<namePart type="termsOfAddress">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">bc</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</namePart>
		</xsl:if>
	</xsl:template>
	<xsl:template name="displayLabel">
		<xsl:if test="marc:subfield[@code='i']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='i']"></xsl:value-of>
			</xsl:attribute>
		</xsl:if>
		<xsl:if test="marc:subfield[@code='3']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='3']"></xsl:value-of>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>
	<xsl:template name="isInvalid">
		<xsl:param name="type"/>
		<xsl:if test="marc:subfield[@code='z'] or marc:subfield[@code='y']">
			<identifier>
				<xsl:attribute name="type">
					<xsl:value-of select="$type"/>
				</xsl:attribute>
				<xsl:attribute name="invalid">
					<xsl:text>yes</xsl:text>
				</xsl:attribute>
				<xsl:if test="marc:subfield[@code='z']">
					<xsl:value-of select="marc:subfield[@code='z']"/>
				</xsl:if>
				<xsl:if test="marc:subfield[@code='y']">
					<xsl:value-of select="marc:subfield[@code='y']"/>
				</xsl:if>
			</identifier>
		</xsl:if>
	</xsl:template>
	<xsl:template name="subtitle">
		<xsl:if test="marc:subfield[@code='b']">
			<subTitle>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:value-of select="marc:subfield[@code='b']"/>
						<!--<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">b</xsl:with-param>									
						</xsl:call-template>-->
					</xsl:with-param>
				</xsl:call-template>
			</subTitle>
		</xsl:if>
	</xsl:template>
	<xsl:template name="script">
		<xsl:param name="scriptCode"></xsl:param>
		<xsl:attribute name="script">
			<xsl:choose>
				<xsl:when test="$scriptCode='(3'">Arabic</xsl:when>
				<xsl:when test="$scriptCode='(B'">Latin</xsl:when>
				<xsl:when test="$scriptCode='$1'">Chinese, Japanese, Korean</xsl:when>
				<xsl:when test="$scriptCode='(N'">Cyrillic</xsl:when>
				<xsl:when test="$scriptCode='(2'">Hebrew</xsl:when>
				<xsl:when test="$scriptCode='(S'">Greek</xsl:when>
			</xsl:choose>
		</xsl:attribute>
	</xsl:template>
	<xsl:template name="parsePart">
		<!-- assumes 773$q= 1:2:3<4
		     with up to 3 levels and one optional start page
		-->
		<xsl:variable name="level1">
			<xsl:choose>
				<xsl:when test="contains(text(),':')">
					<!-- 1:2 -->
					<xsl:value-of select="substring-before(text(),':')"></xsl:value-of>
				</xsl:when>
				<xsl:when test="not(contains(text(),':'))">
					<!-- 1 or 1<3 -->
					<xsl:if test="contains(text(),'&lt;')">
						<!-- 1<3 -->
						<xsl:value-of select="substring-before(text(),'&lt;')"></xsl:value-of>
					</xsl:if>
					<xsl:if test="not(contains(text(),'&lt;'))">
						<!-- 1 -->
						<xsl:value-of select="text()"></xsl:value-of>
					</xsl:if>
				</xsl:when>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici2">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after(text(),$level1),':')">
					<xsl:value-of select="substring(substring-after(text(),$level1),2)"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after(text(),$level1)"></xsl:value-of>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level2">
			<xsl:choose>
				<xsl:when test="contains($sici2,':')">
					<!--  2:3<4  -->
					<xsl:value-of select="substring-before($sici2,':')"></xsl:value-of>
				</xsl:when>
				<xsl:when test="contains($sici2,'&lt;')">
					<!-- 1: 2<4 -->
					<xsl:value-of select="substring-before($sici2,'&lt;')"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici2"></xsl:value-of>
					<!-- 1:2 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="sici3">
			<xsl:choose>
				<xsl:when test="starts-with(substring-after($sici2,$level2),':')">
					<xsl:value-of select="substring(substring-after($sici2,$level2),2)"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="substring-after($sici2,$level2)"></xsl:value-of>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="level3">
			<xsl:choose>
				<xsl:when test="contains($sici3,'&lt;')">
					<!-- 2<4 -->
					<xsl:value-of select="substring-before($sici3,'&lt;')"></xsl:value-of>
				</xsl:when>
				<xsl:otherwise>
					<xsl:value-of select="$sici3"></xsl:value-of>
					<!-- 3 -->
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<xsl:variable name="page">
			<xsl:if test="contains(text(),'&lt;')">
				<xsl:value-of select="substring-after(text(),'&lt;')"></xsl:value-of>
			</xsl:if>
		</xsl:variable>
		<xsl:if test="$level1">
			<detail level="1">
				<number>
					<xsl:value-of select="$level1"></xsl:value-of>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level2">
			<detail level="2">
				<number>
					<xsl:value-of select="$level2"></xsl:value-of>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$level3">
			<detail level="3">
				<number>
					<xsl:value-of select="$level3"></xsl:value-of>
				</number>
			</detail>
		</xsl:if>
		<xsl:if test="$page">
			<extent unit="page">
				<start>
					<xsl:value-of select="$page"></xsl:value-of>
				</start>
			</extent>
		</xsl:if>
	</xsl:template>
	<xsl:template name="getLanguage">
		<xsl:param name="langString"></xsl:param>
		<xsl:param name="controlField008-35-37"></xsl:param>
		<xsl:variable name="length" select="string-length($langString)"></xsl:variable>
		<xsl:choose>
			<xsl:when test="$length=0"></xsl:when>
			<xsl:when test="$controlField008-35-37=substring($langString,1,3)">
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"></xsl:with-param>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"></xsl:with-param>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<language>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="substring($langString,1,3)"></xsl:value-of>
					</languageTerm>
				</language>
				<xsl:call-template name="getLanguage">
					<xsl:with-param name="langString" select="substring($langString,4,$length)"></xsl:with-param>
					<xsl:with-param name="controlField008-35-37" select="$controlField008-35-37"></xsl:with-param>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="isoLanguage">
		<xsl:param name="currentLanguage"></xsl:param>
		<xsl:param name="usedLanguages"></xsl:param>
		<xsl:param name="remainingLanguages"></xsl:param>
		<xsl:choose>
			<xsl:when test="string-length($currentLanguage)=0"></xsl:when>
			<xsl:when test="not(contains($usedLanguages, $currentLanguage))">
				<language>
					<xsl:if test="@code!='a'">
						<xsl:attribute name="objectPart">
							<xsl:choose>
								<xsl:when test="@code='b'">summary or subtitle</xsl:when>
								<xsl:when test="@code='d'">sung or spoken text</xsl:when>
								<xsl:when test="@code='e'">libretto</xsl:when>
								<xsl:when test="@code='f'">table of contents</xsl:when>
								<xsl:when test="@code='g'">accompanying material</xsl:when>
								<xsl:when test="@code='h'">translation</xsl:when>
							</xsl:choose>
						</xsl:attribute>
					</xsl:if>
					<languageTerm authority="iso639-2b" type="code">
						<xsl:value-of select="$currentLanguage"></xsl:value-of>
					</languageTerm>
				</language>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of select="substring($remainingLanguages,4,string-length($remainingLanguages))"></xsl:value-of>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:call-template name="isoLanguage">
					<xsl:with-param name="currentLanguage">
						<xsl:value-of select="substring($remainingLanguages,1,3)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="usedLanguages">
						<xsl:value-of select="concat($usedLanguages,$currentLanguage)"></xsl:value-of>
					</xsl:with-param>
					<xsl:with-param name="remainingLanguages">
						<xsl:value-of select="substring($remainingLanguages,4,string-length($remainingLanguages))"></xsl:value-of>
					</xsl:with-param>
				</xsl:call-template>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="chopBrackets">
		<xsl:param name="chopString"></xsl:param>
		<xsl:variable name="string">
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString" select="$chopString"></xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="substring($string, 1,1)='['">
			<xsl:value-of select="substring($string,2, string-length($string)-2)"></xsl:value-of>
		</xsl:if>
		<xsl:if test="substring($string, 1,1)!='['">
			<xsl:value-of select="$string"></xsl:value-of>
		</xsl:if>
	</xsl:template>
	<xsl:template name="rfcLanguages">
		<xsl:param name="nodeNum"></xsl:param>
		<xsl:param name="usedLanguages"></xsl:param>
		<xsl:param name="controlField008-35-37"></xsl:param>
		<xsl:variable name="currentLanguage" select="."></xsl:variable>
		<xsl:choose>
			<xsl:when test="not($currentLanguage)"></xsl:when>
			<xsl:when test="$currentLanguage!=$controlField008-35-37 and $currentLanguage!='rfc3066'">
				<xsl:if test="not(contains($usedLanguages,$currentLanguage))">
					<language>
						<xsl:if test="@code!='a'">
							<xsl:attribute name="objectPart">
								<xsl:choose>
									<xsl:when test="@code='b'">summary or subtitle</xsl:when>
									<xsl:when test="@code='d'">sung or spoken text</xsl:when>
									<xsl:when test="@code='e'">libretto</xsl:when>
									<xsl:when test="@code='f'">table of contents</xsl:when>
									<xsl:when test="@code='g'">accompanying material</xsl:when>
									<xsl:when test="@code='h'">translation</xsl:when>
								</xsl:choose>
							</xsl:attribute>
						</xsl:if>
						<languageTerm authority="rfc3066" type="code">
							<xsl:value-of select="$currentLanguage"/>
						</languageTerm>
					</language>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<xsl:template name="datafield">
		<xsl:param name="tag"/>
		<xsl:param name="ind1"><xsl:text> </xsl:text></xsl:param>
		<xsl:param name="ind2"><xsl:text> </xsl:text></xsl:param>
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
		<xsl:param name="codes"/>
		<xsl:param name="delimeter"><xsl:text> </xsl:text></xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($codes, @code)">
					<xsl:value-of select="text()"/><xsl:value-of select="$delimeter"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
	</xsl:template>

	<xsl:template name="buildSpaces">
		<xsl:param name="spaces"/>
		<xsl:param name="char"><xsl:text> </xsl:text></xsl:param>
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
		<xsl:param name="punctuation"><xsl:text>.:,;/ </xsl:text></xsl:param>
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
			<xsl:otherwise><xsl:value-of select="$chopString"/></xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationFront">
		<xsl:param name="chopString"/>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains('.:,;/[ ', substring($chopString,1,1))">
				<xsl:call-template name="chopPunctuationFront">
					<xsl:with-param name="chopString" select="substring($chopString,2,$length - 1)"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise><xsl:value-of select="$chopString"/></xsl:otherwise>
		</xsl:choose>
	</xsl:template>
</xsl:stylesheet>$$ WHERE name = 'mods32';

-- Currently, the only difference from naco_normalize is that search_normalize
-- turns apostrophes into spaces, while naco_normalize collapses them.
CREATE OR REPLACE FUNCTION public.search_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

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
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}][/DDOLl/d;

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

CREATE OR REPLACE FUNCTION public.search_normalize_keep_comma( TEXT ) RETURNS TEXT AS $func$
        SELECT public.search_normalize($1,'a');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.search_normalize( TEXT ) RETURNS TEXT AS $func$
	SELECT public.search_normalize($1,'');
$func$ LANGUAGE 'sql' STRICT IMMUTABLE;

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Search Normalize',
	'Apply search normalization rules to the extracted text. A less extreme version of NACO normalization.',
	'search_normalize',
	0
);

UPDATE config.metabib_field_index_norm_map
    SET norm = (
        SELECT id FROM config.index_normalizer WHERE func = 'search_normalize'
    )
    WHERE norm = (
        SELECT id FROM config.index_normalizer WHERE func = 'naco_normalize'
    )
;


-- This could take a long time if you have a very non-English bib database
-- Run it outside of a transaction to avoid lock escalation
SELECT metabib.reingest_metabib_field_entries(record)
    FROM metabib.full_rec
    WHERE tag = '245'
    AND subfield = 'a'
    AND value LIKE '%''%'
;

COMMIT;

-- This is split out because it takes forever to run on large bib collections.
\qecho ************************************************************************
\qecho The following transaction, wrapping upgrades 0679 and 0680, may take a
\qecho *really* long time, and you might be able to run it by itself in
\qecho parallel with other operations using a separate session.
\qecho ************************************************************************

BEGIN;
SELECT evergreen.upgrade_deps_block_check('0679', :eg_version);

-- Address typo in column name
ALTER TABLE config.metabib_class ADD COLUMN buoyant BOOL DEFAULT FALSE NOT NULL;
UPDATE config.metabib_class SET buoyant = bouyant;
ALTER TABLE config.metabib_class DROP COLUMN bouyant;

CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
BEGIN

    value := NEW.value;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;

        NEW.value := value;
    END IF;

    IF NEW.index_vector = ''::tsvector THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN
        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
        value := public.search_normalize(value);
    END IF;

    NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, value);

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Given a string such as a user might type into a search box, prepare
-- two changed variants for TO_TSQUERY(). See
-- http://www.postgresql.org/docs/9.0/static/textsearch-controls.html
-- The first variant is normalized to match indexed documents regardless
-- of diacritics.  The second variant keeps its diacritics for proper
-- highlighting via TS_HEADLINE().
CREATE OR REPLACE
    FUNCTION metabib.autosuggest_prepare_tsquery(orig TEXT) RETURNS TEXT[] AS
$$
DECLARE
    orig_ended_in_space     BOOLEAN;
    result                  RECORD;
    plain                   TEXT;
    normalized              TEXT;
BEGIN
    orig_ended_in_space := orig ~ E'\\s$';

    orig := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(orig, E'\\W+'), ' '
    );

    normalized := public.search_normalize(orig); -- also trim()s
    plain := trim(orig);

    IF NOT orig_ended_in_space THEN
        plain := plain || ':*';
        normalized := normalized || ':*';
    END IF;

    plain := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(plain, E'\\s+'), ' & '
    );
    normalized := ARRAY_TO_STRING(
        evergreen.regexp_split_to_array(normalized, E'\\s+'), ' & '
    );

    RETURN ARRAY[normalized, plain];
END;
$$ LANGUAGE PLPGSQL;


-- Definition of OUT parameters changes, so must drop first
DROP FUNCTION IF EXISTS metabib.suggest_browse_entries (TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER);

CREATE OR REPLACE
    FUNCTION metabib.suggest_browse_entries(
        raw_query_text  TEXT,   -- actually typed by humans at the UI level
        search_class    TEXT,   -- 'alias' or 'class' or 'class|field..', etc
        headline_opts   TEXT,   -- markup options for ts_headline()
        visibility_org  INTEGER,-- null if you don't want opac visibility test
        query_limit     INTEGER,-- use in LIMIT clause of interal query
        normalization   INTEGER -- argument to TS_RANK_CD()
    ) RETURNS TABLE (
        value                   TEXT,   -- plain
        field                   INTEGER,
        buoyant_and_class_match BOOL,
        field_match             BOOL,
        field_weight            INTEGER,
        rank                    REAL,
        buoyant                 BOOL,
        match                   TEXT    -- marked up
    ) AS $func$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    IF visibility_org IS NOT NULL THEN
        opac_visibility_join := '
    JOIN asset.opac_visible_copies aovc ON (
        aovc.record = mbedm.source AND
        aovc.circ_lib IN (SELECT id FROM actor.org_unit_descendants($4))
    )';
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE 'SELECT *, TS_HEADLINE(value, $7, $3) FROM (SELECT DISTINCT
        mbe.value,
        cmf.id,
        cmc.buoyant AND _registered.field_class IS NOT NULL,
        _registered.field = cmf.id,
        cmf.weight,
        TS_RANK_CD(mbe.index_vector, $1, $6),
        cmc.buoyant
    FROM metabib.browse_entry_def_map mbedm
    JOIN metabib.browse_entry mbe ON (mbe.id = mbedm.entry)
    JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
    JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
    '  || search_class_join || opac_visibility_join ||
    ' WHERE $1 @@ mbe.index_vector
    ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
    LIMIT $5) x
    ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
    '   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$func$ LANGUAGE PLPGSQL;


\qecho 
\qecho The following takes about a minute per 100,000 rows in
\qecho metabib.browse_entry on my development system, which is only a VM with
\qecho 4 GB of memory and 2 cores.
\qecho 
\qecho The following is a very loose estimate of how long the next UPDATE
\qecho statement would take to finish on MY machine, based on YOUR number
\qecho of rows in metabib.browse_entry:
\qecho 

SELECT (COUNT(id) / 100000.0) * INTERVAL '1 minute'
    AS "approximate duration of following UPDATE statement"
    FROM metabib.browse_entry;

UPDATE metabib.browse_entry SET index_vector = TO_TSVECTOR(
    'keyword',
    public.search_normalize(
        ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        )
    )
);


SELECT evergreen.upgrade_deps_block_check('0680', :eg_version);

-- Not much use in having identifier-class fields be suggestions. Credit for the idea goes to Ben Shum.
UPDATE config.metabib_field SET browse_field = FALSE WHERE id < 100 AND field_class = 'identifier';


---------------------------------------------------------------------------
-- The rest of this was tested on Evergreen Indiana's dev server, which has
-- a large data set  of 2.6M bibs, and was instrumental in sussing out the
-- needed adjustments.  Thanks, EG-IN!
---------------------------------------------------------------------------

-- GIN indexes are /much/ better for prefix matching, which is important for browse and autosuggest
--Commented out the creation earlier, so we don't need to drop it here.
--DROP INDEX metabib.metabib_browse_entry_index_vector_idx;
CREATE INDEX metabib_browse_entry_index_vector_idx ON metabib.browse_entry USING GIN (index_vector);


-- We need thes to make the autosuggest limiting joins fast
CREATE INDEX browse_entry_def_map_def_idx ON metabib.browse_entry_def_map (def);
CREATE INDEX browse_entry_def_map_entry_idx ON metabib.browse_entry_def_map (entry);
CREATE INDEX browse_entry_def_map_source_idx ON metabib.browse_entry_def_map (source);

-- In practice this will always be ~1 row, and the default of 1000 causes terrible plans
ALTER FUNCTION metabib.search_class_to_registered_components(text) ROWS 1;

-- Reworking of the generated query to act in a sane manner in the face of large datasets
CREATE OR REPLACE
    FUNCTION metabib.suggest_browse_entries(
        raw_query_text  TEXT,   -- actually typed by humans at the UI level
        search_class    TEXT,   -- 'alias' or 'class' or 'class|field..', etc
        headline_opts   TEXT,   -- markup options for ts_headline()
        visibility_org  INTEGER,-- null if you don't want opac visibility test
        query_limit     INTEGER,-- use in LIMIT clause of interal query
        normalization   INTEGER -- argument to TS_RANK_CD()
    ) RETURNS TABLE (
        value                   TEXT,   -- plain
        field                   INTEGER,
        buoyant_and_class_match BOOL,
        field_match             BOOL,
        field_weight            INTEGER,
        rank                    REAL,
        buoyant                 BOOL,
        match                   TEXT    -- marked up
    ) AS $func$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    IF visibility_org IS NOT NULL THEN
        opac_visibility_join := '
    JOIN asset.opac_visible_copies aovc ON (
        aovc.record = x.source AND
        aovc.circ_lib IN (SELECT id FROM actor.org_unit_descendants($4))
    )';
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE '
SELECT  DISTINCT
        x.value,
        x.id,
        x.push,
        x.restrict,
        x.weight,
        x.ts_rank_cd,
        x.buoyant,
        TS_HEADLINE(value, $7, $3)
  FROM  (SELECT DISTINCT
                mbe.value,
                cmf.id,
                cmc.buoyant AND _registered.field_class IS NOT NULL AS push,
                _registered.field = cmf.id AS restrict,
                cmf.weight,
                TS_RANK_CD(mbe.index_vector, $1, $6),
                cmc.buoyant,
                mbedm.source
          FROM  metabib.browse_entry_def_map mbedm

                -- Start with a pre-limited set of 10k possible suggestions. More than that is not going to be useful anyway
                JOIN (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000) mbe ON (mbe.id = mbedm.entry)

                JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
                JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
                '  || search_class_join || '
          ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
          LIMIT 1000) AS x -- This outer limit makes testing for opac visibility usably fast
        ' || opac_visibility_join || '
  ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
  LIMIT $5
'   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

-- This is split out because it was backported to 2.1, but may not exist before upgrades
-- It can safely fail
-- Also, lets say that. <_<
\qecho
\qecho *************************************************************************
\qecho !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
\qecho We are about to apply a patch that may not be needed. It can fail safely.
\qecho !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
\qecho *************************************************************************
\qecho

-- Evergreen DB patch 0693.schema.do_not_despace_issns.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0693', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
-- Delete the index normalizer that was meant to remove spaces from ISSNs
-- but ended up breaking records with multiple ISSNs
DELETE FROM config.metabib_field_index_norm_map WHERE id IN (
    SELECT map.id FROM config.metabib_field_index_norm_map map
        INNER JOIN config.metabib_field cmf ON cmf.id = map.field
        INNER JOIN config.index_normalizer cin ON cin.id = map.norm
    WHERE cin.func = 'replace'
        AND cmf.field_class = 'identifier'
        AND cmf.name = 'issn'
        AND map.params = $$[" ",""]$$
);

-- Reindex records that have more than just a single ISSN
-- to ensure that spaces are maintained
SELECT metabib.reingest_metabib_field_entries(source)
  FROM metabib.identifier_field_entry mife
    INNER JOIN config.metabib_field cmf ON cmf.id = mife.field
  WHERE cmf.field_class = 'identifier'
    AND cmf.name = 'issn'
    AND char_length(value) > 9
;


COMMIT;

-- outside of any transaction

\qecho ************************************************************************
\qecho                  Failures from here down are okay!
\qecho ************************************************************************

SELECT evergreen.upgrade_deps_block_check('0691', :eg_version);

CREATE INDEX poi_po_idx ON acq.po_item (purchase_order);

CREATE INDEX ie_inv_idx on acq.invoice_entry (invoice);
CREATE INDEX ie_po_idx on acq.invoice_entry (purchase_order);
CREATE INDEX ie_li_idx on acq.invoice_entry (lineitem);

CREATE INDEX ii_inv_idx on acq.invoice_item (invoice);
CREATE INDEX ii_po_idx on acq.invoice_item (purchase_order);
CREATE INDEX ii_poi_idx on acq.invoice_item (po_item);

\qecho All Evergreen core database functions have been converted to
\qecho use PLPERLU instead of PLPERL, so we are attempting to remove
\qecho the PLPERL language here; but it is entirely possible that
\qecho existing sites will have custom PLPERL functions that they
\qecho will want to retain, so the following DROP LANGUAGE statement
\qecho may fail, and that is okay.

DROP LANGUAGE plperl;

