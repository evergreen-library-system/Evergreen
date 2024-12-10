/*
 * Copyright (C) 2008 Equinox Software, Inc.
 * Bill Erickson <erickson@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

CREATE OR REPLACE FUNCTION actor.verify_passwd(pw_usr integer, pw_type text, test_passwd text) RETURNS boolean AS $f$
DECLARE
    pw_salt     TEXT;
    api_enabled BOOL;
BEGIN
    /* Returns TRUE if the password provided matches the in-db password.
     * If the password type is salted, we compare the output of CRYPT().
     * NOTE: test_passwd is MD5(salt || MD5(password)) for legacy
     * 'main' passwords.
     *
     * Password type 'api' requires that the user be enabled as an
     * integrator in the openapi.integrator table.
     */

    IF pw_type = 'api' THEN
        SELECT  enabled INTO api_enabled
          FROM  openapi.integrator
          WHERE id = pw_usr;

        IF NOT FOUND OR api_enabled IS FALSE THEN
            -- API integrator account not registered
            RETURN FALSE;
        END IF;
    END IF;

    SELECT INTO pw_salt salt FROM actor.passwd
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF NOT FOUND THEN
        -- no such password
        RETURN FALSE;
    END IF;

    IF pw_salt IS NULL THEN
        -- Password is unsalted, compare the un-CRYPT'ed values.
        RETURN EXISTS (
            SELECT TRUE FROM actor.passwd WHERE
                usr = pw_usr AND
                passwd_type = pw_type AND
                passwd = test_passwd
        );
    END IF;

    RETURN EXISTS (
        SELECT TRUE FROM actor.passwd WHERE
            usr = pw_usr AND
            passwd_type = pw_type AND
            passwd = CRYPT(test_passwd, pw_salt)
    );
END;
$f$ STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION actor.usr_merge_rows( table_name TEXT, col_name TEXT, src_usr INT, dest_usr INT ) RETURNS VOID AS $$
DECLARE
    sel TEXT;
    upd TEXT;
    del TEXT;
    cur_row RECORD;
BEGIN
    sel := 'SELECT id::BIGINT FROM ' || table_name || ' WHERE ' || quote_ident(col_name) || ' = ' || quote_literal(src_usr);
    upd := 'UPDATE ' || table_name || ' SET ' || quote_ident(col_name) || ' = ' || quote_literal(dest_usr) || ' WHERE id = ';
    del := 'DELETE FROM ' || table_name || ' WHERE id = ';
    FOR cur_row IN EXECUTE sel LOOP
        BEGIN
            --RAISE NOTICE 'Attempting to merge % %', table_name, cur_row.id;
            EXECUTE upd || cur_row.id;
        EXCEPTION WHEN unique_violation THEN
            --RAISE NOTICE 'Deleting conflicting % %', table_name, cur_row.id;
            EXECUTE del || cur_row.id;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_merge_rows(TEXT, TEXT, INT, INT) IS $$
Attempts to move each row of the specified table from src_user to dest_user.  
Where conflicts exist, the conflicting "source" row is deleted.
$$;


CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- Bail if src_usr equals dest_usr because the result of merging a
    -- user with itself is not what you want.
    IF src_usr = dest_usr THEN
        RETURN;
    END IF;

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_message SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_request SET canceled_by = dest_usr WHERE canceled_by = src_usr;
	UPDATE action.hold_request_reset_reason_entry SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
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
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
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
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
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

    -- propagate preferred name values from the source user to the
    -- destination user, but only when values are not being replaced.
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr)
    UPDATE actor.usr SET 
        pref_prefix = 
            COALESCE(pref_prefix, (SELECT pref_prefix FROM susr)),
        pref_first_given_name = 
            COALESCE(pref_first_given_name, (SELECT pref_first_given_name FROM susr)),
        pref_second_given_name = 
            COALESCE(pref_second_given_name, (SELECT pref_second_given_name FROM susr)),
        pref_family_name = 
            COALESCE(pref_family_name, (SELECT pref_family_name FROM susr)),
        pref_suffix = 
            COALESCE(pref_suffix, (SELECT pref_suffix FROM susr))
    WHERE id = dest_usr;

    -- Copy and deduplicate name keywords
    -- String -> array -> rows -> DISTINCT -> array -> string
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr),
         dusr AS (SELECT * FROM actor.usr WHERE id = dest_usr)
    UPDATE actor.usr SET name_keywords = (
        WITH keywords AS (
            SELECT DISTINCT UNNEST(
                REGEXP_SPLIT_TO_ARRAY(
                    COALESCE((SELECT name_keywords FROM susr), '') || ' ' ||
                    COALESCE((SELECT name_keywords FROM dusr), ''),  E'\\s+'
                )
            ) AS parts
        ) SELECT STRING_AGG(kw.parts, ' ') FROM keywords kw
    ) WHERE id = dest_usr;

    -- Finally, delete the source user
    PERFORM actor.usr_delete(src_usr,dest_usr);

END;
$$ LANGUAGE plpgsql;



COMMENT ON FUNCTION actor.usr_merge(INT, INT, BOOLEAN, BOOLEAN, BOOLEAN) IS $$
Merges all user date from src_usr to dest_usr.  When collisions occur, 
keep dest_usr's data and delete src_usr's data.
$$;


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

COMMENT ON FUNCTION actor.usr_purge_data(INT, INT) IS $$
Finds rows dependent on a given row in actor.usr and either deletes them
or reassigns them to a different user.
$$;



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

COMMENT ON FUNCTION actor.usr_delete(INT, INT) IS $$
Logically deletes a user.  Removes personally identifiable information,
and purges associated data in other tables.
$$;



CREATE OR REPLACE FUNCTION actor.approve_pending_address(pending_id INT) RETURNS BIGINT AS $$
DECLARE
    old_id INT;
BEGIN
    SELECT INTO old_id replaces FROM actor.usr_address where id = pending_id;
    IF old_id IS NULL THEN
        UPDATE actor.usr_address SET pending = 'f' WHERE id = pending_id;
        RETURN pending_id;
    END IF;
    -- address replaces an existing address
    DELETE FROM actor.usr_address WHERE id = -old_id;
    UPDATE actor.usr_address SET id = -id WHERE id = old_id;
    UPDATE actor.usr_address SET replaces = NULL, id = old_id, pending = 'f' WHERE id = pending_id;
    RETURN old_id;
END
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.approve_pending_address(INT) IS $$
Replaces an address with a pending address.  This is done by giving the pending 
address the ID of the old address.  The replaced address is retained with -id.
$$;

CREATE OR REPLACE FUNCTION actor.change_password (user_id INT, new_pw TEXT, pw_type TEXT DEFAULT 'main')
RETURNS VOID AS $$
DECLARE
    new_salt TEXT;
BEGIN
    SELECT actor.create_salt(pw_type) INTO new_salt;

    IF pw_type = 'main' THEN
        -- Only 'main' passwords are required to have
        -- the extra layer of MD5 hashing.
        PERFORM actor.set_passwd(
            user_id, pw_type, md5(new_salt || md5(new_pw)), new_salt
        );

    ELSE
        PERFORM actor.set_passwd(user_id, pw_type, new_pw, new_salt);
    END IF;
END;
$$ LANGUAGE 'plpgsql';

COMMENT ON FUNCTION actor.change_password(INT,TEXT,TEXT) IS $$
Allows setting a salted password for a user by passing actor.usr id and the text of the password.
$$;

CREATE OR REPLACE FUNCTION container.clear_expired_circ_history_items( 
	 ac_usr IN INTEGER
) RETURNS VOID AS $$
--
-- Delete old circulation bucket items for a specified user.
-- "Old" means older than the interval specified by a
-- user-level setting, if it is so specified.
--
DECLARE
    threshold TIMESTAMP WITH TIME ZONE;
BEGIN
	-- Sanity check
	IF ac_usr IS NULL THEN
		RETURN;
	END IF;
	-- Determine the threshold date that defines "old".  Subtract the
	-- interval from the system date, then truncate to midnight.
	SELECT
		date_trunc( 
			'day',
			now() - CAST( translate( value, '"', '' ) AS INTERVAL )
		)
	INTO
		threshold
	FROM
		actor.usr_setting
	WHERE
		usr = ac_usr
		AND name = 'patron.max_reading_list_interval';
	--
	IF threshold is null THEN
		-- No interval defined; don't delete anything
		-- RAISE NOTICE 'No interval defined for user %', ac_usr;
		return;
	END IF;
	--
	-- RAISE NOTICE 'Date threshold: %', threshold;
	--
	-- Threshold found; do the delete
	delete from container.copy_bucket_item
	where
		bucket in
		(
			select
				id
			from
				container.copy_bucket
			where
				owner = ac_usr
				and btype = 'circ_history'
		)
		and create_time < threshold;
	--
	RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION container.clear_expired_circ_history_items( INTEGER ) IS $$
Delete old circulation bucket items for a specified user.
"Old" means older than the interval specified by a
user-level setting, if it is so specified.
$$;

CREATE OR REPLACE FUNCTION container.clear_all_expired_circ_history_items( )
RETURNS VOID AS $$
--
-- Delete expired circulation bucket items for all users that have
-- a setting for patron.max_reading_list_interval.
--
DECLARE
    today        TIMESTAMP WITH TIME ZONE;
    threshold    TIMESTAMP WITH TIME ZONE;
	usr_setting  RECORD;
BEGIN
	SELECT date_trunc( 'day', now() ) INTO today;
	--
	FOR usr_setting in
		SELECT
			usr,
			value
		FROM
			actor.usr_setting
		WHERE
			name = 'patron.max_reading_list_interval'
	LOOP
		--
		-- Make sure the setting is a valid interval
		--
		BEGIN
			threshold := today - CAST( translate( usr_setting.value, '"', '' ) AS INTERVAL );
		EXCEPTION
			WHEN OTHERS THEN
				RAISE NOTICE 'Invalid setting patron.max_reading_list_interval for user %: ''%''',
					usr_setting.usr, usr_setting.value;
				CONTINUE;
		END;
		--
		--RAISE NOTICE 'User % threshold %', usr_setting.usr, threshold;
		--
    	DELETE FROM container.copy_bucket_item
    	WHERE
        	bucket IN
        	(
        	    SELECT
        	        id
        	    FROM
        	        container.copy_bucket
        	    WHERE
        	        owner = usr_setting.usr
        	        AND btype = 'circ_history'
        	)
        	AND create_time < threshold;
	END LOOP;
	--
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION container.clear_all_expired_circ_history_items( ) IS $$
Delete expired circulation bucket items for all users that have
a setting for patron.max_reading_list_interval.
$$;

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- we don't merge bib -1
    IF target_record = -1 OR source_record = -1 THEN
       RETURN 0;
    END IF;

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
			' tag="856"' ||
			' ind1="' || FIRST(ind1) || '"'  ||
			' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

	-- Find and move metarecords to the target record
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
			AND owning_lib = source_cn.owning_lib
			AND record = target_record
			AND NOT deleted;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial subscriptions targeting the source record ...
	FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.subscription
		  SET	record_entry = target_record
		  WHERE	id = ser_sub.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find booking resource types targeting the source record ...
	FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	booking.resource_type
		  SET	record = target_record
		  WHERE	id = booking.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq lineitems targeting the source record ...
	FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.lineitem
		  SET	eg_bib_id = target_record
		  WHERE	id = acq_lineitem.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq user purchase requests targeting the source record ...
	FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.user_request
		  SET	eg_bib = target_record
		  WHERE	id = acq_request.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find parts attached to the source ...
	FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

		SELECT	INTO target_part *
		  FROM	biblio.monograph_part
		  WHERE	label = source_part.label
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copy-part maps to that, and ...
			UPDATE	asset.copy_part_map
			  SET	part = target_part.id
			  WHERE	part = source_part.id;

			-- ... move P holds to the move-target part
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_part.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the part to the target record
			UPDATE	biblio.monograph_part
			  SET	record = target_record
			  WHERE	id = source_part.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find multi_home items attached to the source ...
	FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	biblio.peer_bib_copy_map
		  SET	peer_record = target_record
		  WHERE	id = multi_home.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- And delete mappings where the item's home bib was merged with the peer bib
	DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
		SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
		FROM asset.copy WHERE id = target_copy
	);

    -- Apply merge tracking
    UPDATE biblio.record_entry 
        SET merge_date = NOW() WHERE id = target_record;

    UPDATE biblio.record_entry
        SET merge_date = NOW(), merged_to = target_record
        WHERE id = source_record;

    -- replace book bag entries of source_record with target_record
    UPDATE container.biblio_record_entry_bucket_item
        SET target_biblio_record_entry = target_record
        WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'bookbag')
        AND target_biblio_record_entry = source_record;

    -- move over record notes 
    UPDATE biblio.record_note 
        SET record = target_record, value = CONCAT(value,'; note merged from ',source_record::TEXT) 
        WHERE record = source_record
        AND NOT deleted;

    -- add note to record merge 
    INSERT INTO biblio.record_note (record, value) 
        VALUES (target_record,CONCAT('record ',source_record::TEXT,' merged on ',NOW()::TEXT));

    -- Finally, "delete" the source record
    UPDATE biblio.record_entry SET active = FALSE WHERE id = source_record;
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

-- Authority ingest routines

CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT) RETURNS SETOF BIGINT AS $func$
    SELECT authority.propagate_changes( authority, bib ) FROM authority.bib_linking WHERE authority = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.map_thesaurus_to_control_set () RETURNS TRIGGER AS $func$
BEGIN
    IF NEW.control_set IS NULL THEN
        SELECT  control_set INTO NEW.control_set
          FROM  authority.thesaurus
          WHERE authority.extract_thesaurus(NEW.marc) = code;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.reingest_authority_rec_descriptor( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.rec_descriptor WHERE record = auth_id;
    INSERT INTO authority.rec_descriptor (record, record_status, encoding_level, thesaurus)
        SELECT  auth_id,
                vandelay.marc21_extract_fixed_field(marc,'RecStat'),
                vandelay.marc21_extract_fixed_field(marc,'ELvl'),
                authority.extract_thesaurus(marc)
          FROM  authority.record_entry
          WHERE id = auth_id;
    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.reingest_authority_full_rec( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.full_rec WHERE record = auth_id;
    INSERT INTO authority.full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM authority.flatten_marc( auth_id );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- Given an authority record's ID, control set ID (if known), and marc::XML,
-- return all links to other authority records in the form of rows that
-- can be inserted into authority.authority_linking.
CREATE OR REPLACE FUNCTION authority.calculate_authority_linking(
    rec_id BIGINT, rec_control_set INT, rec_marc_xml XML
) RETURNS SETOF authority.authority_linking AS $func$
DECLARE
    acsaf       authority.control_set_authority_field%ROWTYPE;
    link        TEXT;
    aal         authority.authority_linking%ROWTYPE;
BEGIN
    IF rec_control_set IS NULL THEN
        -- No control_set on record?  Guess at one
        SELECT control_set INTO rec_control_set
            FROM authority.control_set_authority_field
            WHERE tag IN (
                SELECT UNNEST(
                    XPATH('//*[starts-with(@tag,"1")]/@tag',rec_marc_xml)::TEXT[]
                )
            ) LIMIT 1;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not even guess at control set for authority record %', rec_id;
            RETURN;
        END IF;
    END IF;

    aal.source := rec_id;

    FOR acsaf IN
        SELECT * FROM authority.control_set_authority_field
        WHERE control_set = rec_control_set
            AND linking_subfield IS NOT NULL
            AND main_entry IS NOT NULL
    LOOP
        -- Loop over the trailing-number contents of all linking subfields
        FOR link IN
            SELECT  SUBSTRING( x::TEXT, '\d+$' )
              FROM  UNNEST(
                        XPATH(
                            '//*[@tag="'
                                || acsaf.tag
                                || '"]/*[@code="'
                                || acsaf.linking_subfield
                                || '"]/text()',
                            rec_marc_xml
                        )
                    ) x
        LOOP

            -- Ignore links that are null, malformed, circular, or point to
            -- non-existent authority records.
            IF link IS NOT NULL AND link::BIGINT <> rec_id THEN
                PERFORM * FROM authority.record_entry WHERE id = link::BIGINT;
                IF FOUND THEN
                    aal.target := link::BIGINT;
                    aal.field := acsaf.id;
                    RETURN NEXT aal;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-- Ingest triggers
CREATE TRIGGER fingerprint_tgr BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.fingerprint_trigger ('eng','BKS');
CREATE TRIGGER bbb_simple_rec_trigger AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger ();

CREATE TRIGGER map_thesaurus_to_control_set BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.map_thesaurus_to_control_set ();

-- Utility routines, callable via cstore

CREATE OR REPLACE FUNCTION config.interval_to_seconds( interval_val INTERVAL )
RETURNS INTEGER AS $$
BEGIN
	RETURN EXTRACT( EPOCH FROM interval_val );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION config.interval_to_seconds( interval_string TEXT )
RETURNS INTEGER AS $$
BEGIN
	RETURN config.interval_to_seconds( interval_string::INTERVAL );
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
            item_data.internal_id,
            item_data.opac_visible,
            item_data.stat_cat_data,
            item_data.parts_data,
            item_data.import_error,
            item_data.error_detail
        );
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER ingest_item_trigger
    AFTER INSERT OR UPDATE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.ingest_bib_items();


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

CREATE OR REPLACE FUNCTION evergreen.coded_value_map_normalizer( input TEXT, ctype TEXT ) 
    RETURNS TEXT AS $F$
        SELECT COALESCE(value,$1) 
            FROM config.coded_value_map 
            WHERE ctype = $2 AND code = $1;
$F$ LANGUAGE SQL;

-- user activity functions --

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
CREATE OR REPLACE FUNCTION actor.insert_usr_activity(
        usr INT,
        ewho TEXT,
        ewhat TEXT,
        ehow TEXT,
        edata TEXT DEFAULT NULL
    ) RETURNS SETOF actor.usr_activity AS $$
DECLARE
    new_row actor.usr_activity%ROWTYPE;
BEGIN
    SELECT id INTO new_row.etype FROM actor.usr_activity_get_type(ewho, ewhat, ehow);
    IF FOUND THEN
        new_row.usr := usr;
        new_row.event_data := edata;
        INSERT INTO actor.usr_activity (usr, etype, event_data)
            VALUES (usr, new_row.etype, new_row.event_data)
            RETURNING * INTO new_row;
        RETURN NEXT new_row;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION evergreen.rel_bump(terms TEXT[], value TEXT, bumps TEXT[], mults NUMERIC[]) RETURNS NUMERIC AS
$BODY$
use strict;
my ($terms,$value,$bumps,$mults) = @_;

my $retval = 1;

for (my $id = 0; $id < @$bumps; $id++) {
        if ($bumps->[$id] eq 'first_word') {
                $retval *= $mults->[$id] if ($value =~ /^$terms->[0]/);
        } elsif ($bumps->[$id] eq 'full_match') {
                my $fullmatch = join(' ', @$terms);
                $retval *= $mults->[$id] if ($value =~ /^$fullmatch$/);
        } elsif ($bumps->[$id] eq 'word_order') {
                my $wordorder = join('.*', @$terms);
                $retval *= $mults->[$id] if ($value =~ /$wordorder/);
        }
}
return $retval;
$BODY$ LANGUAGE plperlu IMMUTABLE STRICT COST 100;

-- user activity functions --


-- find the most relevant set of credentials for the Z source and org
CREATE OR REPLACE FUNCTION config.z3950_source_credentials_lookup
        (source TEXT, owner INTEGER) 
        RETURNS config.z3950_source_credentials AS $$

    SELECT creds.* 
    FROM config.z3950_source_credentials creds
        JOIN actor.org_unit aou ON (aou.id = creds.owner)
        JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
    WHERE creds.source = $1 AND creds.owner IN ( 
        SELECT id FROM actor.org_unit_ancestors($2) 
    )
    ORDER BY aout.depth DESC LIMIT 1;

$$ LANGUAGE SQL STABLE;

-- since we are not exposing config.z3950_source_credentials
-- via the IDL, providing a stored proc gives us a way to
-- set values in the table via cstore
CREATE OR REPLACE FUNCTION config.z3950_source_credentials_apply
        (src TEXT, org INTEGER, uname TEXT, passwd TEXT) 
        RETURNS VOID AS $$
BEGIN
    PERFORM 1 FROM config.z3950_source_credentials
        WHERE owner = org AND source = src;

    IF FOUND THEN
        IF COALESCE(uname, '') = '' AND COALESCE(passwd, '') = '' THEN
            DELETE FROM config.z3950_source_credentials 
                WHERE owner = org AND source = src;
        ELSE 
            UPDATE config.z3950_source_credentials 
                SET username = uname, password = passwd
                WHERE owner = org AND source = src;
        END IF;
    ELSE
        IF COALESCE(uname, '') <> '' OR COALESCE(passwd, '') <> '' THEN
            INSERT INTO config.z3950_source_credentials
                (source, owner, username, password) 
                VALUES (src, org, uname, passwd);
        END IF;
    END IF;
END;
$$ LANGUAGE PLPGSQL;

-- Handy function for transforming marc to a variant available on config.xml_transform
CREATE OR REPLACE FUNCTION evergreen.marc_to (marc text, xfrm text) RETURNS TEXT AS $$
    SELECT evergreen.xml_pretty_print(xslt_process($1,xslt)::XML)::TEXT FROM config.xml_transform WHERE name = $2;
$$ LANGUAGE SQL;

