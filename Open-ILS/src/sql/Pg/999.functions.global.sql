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


CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT ) RETURNS VOID AS $$
BEGIN

    -- actor.*
    UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
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
    PERFORM actor.usr_merge_rows('container.user_bucket_item', 'target_user', src_usr, dest_usr);

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


    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.template', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.report', 'owner', src_usr, dest_usr);
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
        PERFORM actor.usr_merge_rows('reporter.schedule', 'runner', src_usr, dest_usr);
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

    -- Finally, clean and delete the source user
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_merge(INT, INT) IS $$
/**
 * Merges all user date from src_usr to dest_usr.  When collisions occur, 
 * keep dest_usr's data and delete src_usr's data.
 */
$$;

