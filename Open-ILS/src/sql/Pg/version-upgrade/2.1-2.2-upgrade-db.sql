--Upgrade Script for 2.1 to 2.2-alpha1
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2-alpha1');
-- DROP objects that might have existed from a prior run of 0526
-- Yes this is ironic.
DROP TABLE IF EXISTS config.db_patch_dependencies;
ALTER TABLE config.upgrade_log DROP COLUMN applied_to;
DROP FUNCTION evergreen.upgrade_list_applied_deprecates(TEXT);
DROP FUNCTION evergreen.upgrade_list_applied_supersedes(TEXT);


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

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> OLD.status THEN
        NEW.status_changed_time := now();
        IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
            NEW.active_date := now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
                AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
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
                    AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
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

CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
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
    END IF;

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
('finance', oils_i18n_gettext('config.settings_group.finances', 'Finanaces', 'coust', 'label')),
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

ALTER TABLE authority.control_set_authority_field ADD COLUMN nfi CHAR(1);

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

ALTER TABLE actor.org_unit_setting ADD CONSTRAINT aous_must_be_json CHECK ( evergreen.is_json(value) );

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

COMMIT;
