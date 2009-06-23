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
/**
 * Attempts to move each row of the specified table from src_user to dest_user.  
 * Where conflicts exist, the conflicting "source" row is deleted.
 */
$$;


CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
BEGIN

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

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
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
    PERFORM actor.usr_merge_rows('container.biblio_record_entry_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.call_number_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.copy_bucket', 'owner', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('container.user_bucket', 'owner', src_usr, dest_usr);
	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
    PERFORM actor.usr_merge_rows('vandelay.queue', 'owner', src_usr, dest_usr);

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

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
    PERFORM actor.usr_merge_rows('acq.picklist', 'owner', src_usr, dest_usr);
    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
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
        PERFORM actor.usr_merge_rows('reporter.template_folder', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.report_folder', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.output_folder', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_merge(INT, INT, BOOLEAN, BOOLEAN, BOOLEAN) IS $$
/**
 * Merges all user date from src_usr to dest_usr.  When collisions occur, 
 * keep dest_usr's data and delete src_usr's data.
 */
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
/**
 * Replaces an address with a pending address.  This is done by giving the pending 
 * address the ID of the old address.  The replaced address is retained with -id.
 */
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
/*
 * Delete old circulation bucket items for a specified user.
 * "Old" means older than the interval specified by a
 * user-level setting, if it is so specified.
*/
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
/*
 * Delete expired circulation bucket items for all users that have
 * a setting for patron.max_reading_list_interval.
*/
$$


CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
	moved_objects INT := 0;
	source_cn     asset.call_number%ROWTYPE;
	target_cn     asset.call_number%ROWTYPE;
	metarec       metabib.metarecord%ROWTYPE;
	hold          action.hold_request%ROWTYPE;
	ser_rec       serial.record_entry%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        SELECT  COUNT(*) INTO counter
          FROM  xpath_table(
                    'id',
                    'marc',
                    'acq.lineitem',
                    '//*[@tag="856"]',
                    'id=' || lineitem
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim" tag="856">' ||
                        array_to_string(
                            array_accum(
                                '<subfield code="' || subfield || '">' ||
                                regexp_replace(
                                    regexp_replace(
                                        regexp_replace(data,'&','&amp;','g'),
                                        '>', '&gt;', 'g'
                                    ),
                                    '<', '&lt;', 'g'
                                ) || '</subfield>'
                            ), ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,subfield text,data text);

            uri_text := uri_text || uri_datafield;
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
			AND owning_lib = source_cn.owning_lib
			AND record = target_record;

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

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

