--Upgrade Script for 3.5.0 to 3.5.1
\set eg_version '''3.5.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.5.1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1206', :eg_version);

CREATE OR REPLACE FUNCTION
    action.hold_request_regen_copy_maps(
        hold_id INTEGER, copy_ids INTEGER[]) RETURNS VOID AS $$
    DELETE FROM action.hold_copy_map WHERE hold = $1;
    INSERT INTO action.hold_copy_map (hold, target_copy) SELECT DISTINCT $1, UNNEST($2);
$$ LANGUAGE SQL;


SELECT evergreen.upgrade_deps_block_check('1207', :eg_version);

UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.alert_text',
            'Text to be inserted into Print Templates in place of {{includes.alert_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.alert_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.event_text',
            'Text to be inserted into Print Templates in place of {{includes.event_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.event_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.footer_text',
            'Text to be inserted into Print Templates in place of {{includes.footer_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.footer_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.header_text',
            'Text to be inserted into Print Templates in place of {{includes.header_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.header_text';
UPDATE config.org_unit_setting_type 
        SET description = oils_i18n_gettext(
            'circ.staff_client.receipt.notice_text',
            'Text to be inserted into Print Templates in place of {{includes.notice_text}}',
            'cwst', 'label') 
        WHERE name = 'circ.staff_client.receipt.notice_text';


SELECT evergreen.upgrade_deps_block_check('1208', :eg_version);

CREATE OR REPLACE FUNCTION action.emergency_closing_stage_2_circ ( circ_closing_entry INT )
    RETURNS BOOL AS $$
DECLARE
    circ            action.circulation%ROWTYPE;
    e_closing       action.emergency_closing%ROWTYPE;
    e_c_circ        action.emergency_closing_circulation%ROWTYPE;
    closing         actor.org_unit_closed%ROWTYPE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    bill            money.billing%ROWTYPE;
    last_bill       money.billing%ROWTYPE;
    day_number      INT;
    hoo_close       TIME WITHOUT TIME ZONE;
    plus_days       INT;
    avoid_negative  BOOL;
    extend_grace    BOOL;
    new_due_date    TEXT;
BEGIN
    -- Gather objects involved
    SELECT  * INTO e_c_circ
      FROM  action.emergency_closing_circulation
      WHERE id = circ_closing_entry;

    IF e_c_circ.process_time IS NOT NULL THEN
        -- Already processed ... moving on
        RETURN FALSE;
    END IF;

    SELECT  * INTO e_closing
      FROM  action.emergency_closing
      WHERE id = e_c_circ.emergency_closing;

    IF e_closing.process_start_time IS NULL THEN
        -- Huh... that's odd. And wrong.
        RETURN FALSE;
    END IF;

    SELECT  * INTO closing
      FROM  actor.org_unit_closed
      WHERE emergency_closing = e_closing.id;

    SELECT  * INTO circ
      FROM  action.circulation
      WHERE id = e_c_circ.circulation;

    -- Record the processing
    UPDATE  action.emergency_closing_circulation
      SET   original_due_date = circ.due_date,
            process_time = NOW()
      WHERE id = circ_closing_entry;

    UPDATE  action.emergency_closing
      SET   last_update_time = NOW()
      WHERE id = e_closing.id;

    SELECT value::BOOL INTO avoid_negative FROM actor.org_unit_ancestor_setting('bill.prohibit_negative_balance_on_overdues', circ.circ_lib);
    SELECT value::BOOL INTO extend_grace FROM actor.org_unit_ancestor_setting('circ.grace.extend', circ.circ_lib);

    new_due_date := evergreen.find_next_open_time( closing.org_unit, circ.due_date, EXTRACT(EPOCH FROM circ.duration)::INT % 86400 > 0 )::TEXT;
    UPDATE action.circulation SET due_date = new_due_date::TIMESTAMPTZ WHERE id = circ.id;

    -- Now, see if we need to get rid of some fines
    SELECT  * INTO last_bill
      FROM  money.billing b
      WHERE b.xact = circ.id
            AND NOT b.voided
            AND b.btype = 1
      ORDER BY billing_ts DESC
      LIMIT 1;

    FOR bill IN
        SELECT  *
          FROM  money.billing b
          WHERE b.xact = circ.id
                AND b.btype = 1
                AND NOT b.voided
                AND (
                    b.billing_ts BETWEEN closing.close_start AND new_due_date::TIMESTAMPTZ
                    OR (extend_grace AND last_bill.billing_ts <= new_due_date::TIMESTAMPTZ + circ.grace_period)
                )
                AND NOT EXISTS (SELECT 1 FROM money.account_adjustment a WHERE a.billing = b.id)
          ORDER BY billing_ts
    LOOP
        IF avoid_negative THEN
            PERFORM FROM money.materialized_billable_xact_summary WHERE id = circ.id AND balance_owed < bill.amount;
            EXIT WHEN FOUND; -- We can't go negative, and voiding this bill would do that...
        END IF;

        UPDATE  money.billing
          SET   voided = TRUE,
                void_time = NOW(),
                note = COALESCE(note,'') || ' :: Voided by emergency closing handler'
          WHERE id = bill.id;
    END LOOP;
    
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.emergency_closing_stage_2_reservation ( res_closing_entry INT )
    RETURNS BOOL AS $$
DECLARE
    res             booking.reservation%ROWTYPE;
    e_closing       action.emergency_closing%ROWTYPE;
    e_c_res         action.emergency_closing_reservation%ROWTYPE;
    closing         actor.org_unit_closed%ROWTYPE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    bill            money.billing%ROWTYPE;
    day_number      INT;
    hoo_close       TIME WITHOUT TIME ZONE;
    plus_days       INT;
    avoid_negative  BOOL;
    new_due_date    TEXT;
BEGIN
    -- Gather objects involved
    SELECT  * INTO e_c_res
      FROM  action.emergency_closing_reservation
      WHERE id = res_closing_entry;

    IF e_c_res.process_time IS NOT NULL THEN
        -- Already processed ... moving on
        RETURN FALSE;
    END IF;

    SELECT  * INTO e_closing
      FROM  action.emergency_closing
      WHERE id = e_c_res.emergency_closing;

    IF e_closing.process_start_time IS NULL THEN
        -- Huh... that's odd. And wrong.
        RETURN FALSE;
    END IF;

    SELECT  * INTO closing
      FROM  actor.org_unit_closed
      WHERE emergency_closing = e_closing.id;

    SELECT  * INTO res
      FROM  booking.reservation
      WHERE id = e_c_res.reservation;

    IF res.pickup_lib IS NULL THEN -- Need to be far enough along to have a pickup lib
        RETURN FALSE;
    END IF;

    -- Record the processing
    UPDATE  action.emergency_closing_reservation
      SET   original_end_time = res.end_time,
            process_time = NOW()
      WHERE id = res_closing_entry;

    UPDATE  action.emergency_closing
      SET   last_update_time = NOW()
      WHERE id = e_closing.id;

    SELECT value::BOOL INTO avoid_negative FROM actor.org_unit_ancestor_setting('bill.prohibit_negative_balance_on_overdues', res.pickup_lib);

    new_due_date := evergreen.find_next_open_time( closing.org_unit, res.end_time, EXTRACT(EPOCH FROM res.booking_interval)::INT % 86400 > 0 )::TEXT;
    UPDATE booking.reservation SET end_time = new_due_date::TIMESTAMPTZ WHERE id = res.id;

    -- Now, see if we need to get rid of some fines
    FOR bill IN
        SELECT  *
          FROM  money.billing b
          WHERE b.xact = res.id
                AND b.btype = 1
                AND NOT b.voided
                AND b.billing_ts BETWEEN closing.close_start AND new_due_date::TIMESTAMPTZ
                AND NOT EXISTS (SELECT 1 FROM money.account_adjustment a WHERE a.billing = b.id)
    LOOP
        IF avoid_negative THEN
            PERFORM FROM money.materialized_billable_xact_summary WHERE id = res.id AND balance_owed < bill.amount;
            EXIT WHEN FOUND; -- We can't go negative, and voiding this bill would do that...
        END IF;

        UPDATE  money.billing
          SET   voided = TRUE,
                void_time = NOW(),
                note = COALESCE(note,'') || ' :: Voided by emergency closing handler'
          WHERE id = bill.id;
    END LOOP;
    
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1209', :eg_version);

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
    item_prox               INT;
    home_prox               INT;
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
    IF NOT renewal AND item_object.status <> 8 AND item_object.status NOT IN (
        (SELECT id FROM config.copy_status WHERE is_available) ) THEN 
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

    -- Proximity of user's home_ou to circ_ou to see if penalties should be ignored.
    SELECT INTO home_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = circ_ou;

    -- Proximity of user's home_ou to item circ_lib to see if penalties should be ignored.
    SELECT INTO item_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = item_object.circ_lib;

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
                AND (csp.ignore_proximity IS NULL
                     OR csp.ignore_proximity < home_prox
                     OR csp.ignore_proximity < item_prox)
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
                    AND circ.xact_finish IS NULL
                    AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
                    AND (copy.circ_modifier IN (SELECT circ_mod FROM config.circ_limit_set_circ_mod_map WHERE limit_set = circ_limit_set.id)
                        OR copy.location IN (SELECT copy_loc FROM config.circ_limit_set_copy_loc_map WHERE limit_set = circ_limit_set.id)
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


SELECT evergreen.upgrade_deps_block_check('1211', :eg_version); -- Dyrcona/rhamby/gmcharlt

CREATE OR REPLACE FUNCTION actor.usr_delete(
	src_usr  IN INTEGER,
	dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	old_profile actor.usr.profile%type;
	old_home_ou actor.usr.home_ou%type;
	new_profile actor.usr.profile%type;
	new_home_ou actor.usr.home_ou%type;
	new_name    text;
	new_dob     actor.usr.dob%type;
BEGIN
	SELECT
		id || '-PURGED-' || now(),
		profile,
		home_ou,
		dob
	INTO
		new_name,
		old_profile,
		old_home_ou,
		new_dob
	FROM
		actor.usr
	WHERE
		id = src_usr;
	--
	-- Quit if no such user
	--
	IF old_profile IS NULL THEN
		RETURN;
	END IF;
	--
	perform actor.usr_purge_data( src_usr, dest_usr );
	--
	-- Find the root grp_tree and the root org_unit.  This would be simpler if we 
	-- could assume that there is only one root.  Theoretically, someday, maybe,
	-- there could be multiple roots, so we take extra trouble to get the right ones.
	--
	SELECT
		id
	INTO
		new_profile
	FROM
		permission.grp_ancestors( old_profile )
	WHERE
		parent is null;
	--
	SELECT
		id
	INTO
		new_home_ou
	FROM
		actor.org_unit_ancestors( old_home_ou )
	WHERE
		parent_ou is null;
	--
	-- Truncate date of birth
	--
	IF new_dob IS NOT NULL THEN
		new_dob := date_trunc( 'year', new_dob );
	END IF;
	--
	UPDATE
		actor.usr
		SET
			card = NULL,
			profile = new_profile,
			usrname = new_name,
			email = NULL,
			passwd = random()::text,
			standing = DEFAULT,
			ident_type = 
			(
				SELECT MIN( id )
				FROM config.identification_type
			),
			ident_value = NULL,
			ident_type2 = NULL,
			ident_value2 = NULL,
			net_access_level = DEFAULT,
			photo_url = NULL,
			prefix = NULL,
			first_given_name = new_name,
			second_given_name = NULL,
			family_name = new_name,
			suffix = NULL,
			alias = NULL,
            guardian = NULL,
			day_phone = NULL,
			evening_phone = NULL,
			other_phone = NULL,
			mailing_address = NULL,
			billing_address = NULL,
			home_ou = new_home_ou,
			dob = new_dob,
			active = FALSE,
			master_account = DEFAULT, 
			super_user = DEFAULT,
			barred = FALSE,
			deleted = TRUE,
			juvenile = DEFAULT,
			usrgroup = 0,
			claims_returned_count = DEFAULT,
			credit_forward_balance = DEFAULT,
			last_xact_id = DEFAULT,
			alert_message = NULL,
			pref_prefix = NULL,
			pref_first_given_name = NULL,
			pref_second_given_name = NULL,
			pref_family_name = NULL,
			pref_suffix = NULL,
			name_keywords = NULL,
			create_date = now(),
			expire_date = now()
	WHERE
		id = src_usr;
END;
$$ LANGUAGE plpgsql;

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
