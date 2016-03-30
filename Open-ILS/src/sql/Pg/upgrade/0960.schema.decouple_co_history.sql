
BEGIN;

-- TODO process to delete history items once the age threshold 
-- history.circ.retention_age is reached?

SELECT evergreen.upgrade_deps_block_check('0960', :eg_version); 

CREATE TABLE action.usr_circ_history (
    id           BIGSERIAL PRIMARY KEY,
    usr          INTEGER NOT NULL REFERENCES actor.usr(id)
                 DEFERRABLE INITIALLY DEFERRED,
    xact_start   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    target_copy  BIGINT NOT NULL,
    due_date     TIMESTAMP WITH TIME ZONE NOT NULL,
    checkin_time TIMESTAMP WITH TIME ZONE,
    source_circ  BIGINT REFERENCES action.circulation(id)
                 ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION action.maintain_usr_circ_history() 
    RETURNS TRIGGER AS $FUNK$
DECLARE
    cur_circ  BIGINT;
    first_circ BIGINT;
BEGIN                                                                          

    -- Any retention value signifies history is enabled.
    -- This assumes that clearing these values via external 
    -- process deletes the action.usr_circ_history rows.
    -- TODO: replace these settings w/ a single bool setting?
    PERFORM 1 FROM actor.usr_setting 
        WHERE usr = NEW.usr AND value IS NOT NULL AND name IN (
            'history.circ.retention_age', 
            'history.circ.retention_start'
        );

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.parent_circ IS NULL THEN
        -- Starting a new circulation.  Insert the history row.
        INSERT INTO action.usr_circ_history 
            (usr, xact_start, target_copy, due_date, source_circ)
        VALUES (
            NEW.usr, 
            NEW.xact_start, 
            NEW.target_copy, 
            NEW.due_date, 
            NEW.id
        );

        RETURN NEW;
    END IF;

    -- find the first and last circs in the circ chain 
    -- for the currently modified circ.
    FOR cur_circ IN SELECT id FROM action.circ_chain(NEW.id) LOOP
        IF first_circ IS NULL THEN
            first_circ := cur_circ;
            CONTINUE;
        END IF;
        -- Allow the loop to continue so that at as the loop
        -- completes cur_circ points to the final circulation.
    END LOOP;

    IF NEW.id <> cur_circ THEN
        -- Modifying an intermediate circ.  Ignore it.
        RETURN NEW;
    END IF;

    -- Update the due_date/checkin_time on the history row if the current 
    -- circ is the last circ in the chain and an update is warranted.

    UPDATE action.usr_circ_history 
        SET 
            due_date = NEW.due_date,
            checkin_time = NEW.checkin_time
        WHERE 
            source_circ = first_circ 
            AND (
                due_date <> NEW.due_date OR (
                    (checkin_time IS NULL AND NEW.checkin_time IS NOT NULL) OR
                    (checkin_time IS NOT NULL AND NEW.checkin_time IS NULL) OR
                    (checkin_time <> NEW.checkin_time)
                )
            );
    RETURN NEW;
END;                                                                           
$FUNK$ LANGUAGE PLPGSQL; 

CREATE TRIGGER maintain_usr_circ_history_tgr 
    AFTER INSERT OR UPDATE ON action.circulation 
    FOR EACH ROW EXECUTE PROCEDURE action.maintain_usr_circ_history();

UPDATE action_trigger.hook 
    SET core_type = 'auch' 
    WHERE key ~ '^circ.format.history.'; 

UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Circulation History

    [% FOR circ IN target %]
            [% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
            Barcode: [% circ.target_copy.barcode %]
            Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]
            Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
            Returned: [%
                date.format(
                    helpers.format_date(circ.checkin_time), '%Y-%m-%d') 
                    IF circ.checkin_time; 
            %]
    [% END %]
$$
WHERE id = 25 AND template = 
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Circulation History

    [% FOR circ IN target %]
            [% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
            Barcode: [% circ.target_copy.barcode %]
            Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]
            Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
            Returned: [% date.format(helpers.format_date(circ.checkin_time), '%Y-%m-%d') %]
    [% END %]
$$;

-- avoid TT undef date errors
UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            <div>Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]</div>
            <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
            <div>Returned: [%
                date.format(
                    helpers.format_date(circ.checkin_time), '%Y-%m-%d') 
                    IF circ.checkin_time; -%]
            </div>
        </li>
    [% END %]
    </ol>
</div>
$$
WHERE id = 26 AND template = -- only replace template if it matches stock
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            <div>Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]</div>
            <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
            <div>Returned: [% date.format(helpers.format_date(circ.checkin_time), '%Y-%m-%d') %]</div>
        </li>
    [% END %]
    </ol>
</div>
$$;

-- NOTE: ^-- stock CSV template does not include checkin_time, so 
-- no modifications are required.

-- Create circ history rows for existing circ history data.
DO $FUNK$
DECLARE
    cur_usr   INTEGER;
    cur_circ  action.circulation%ROWTYPE;
    last_circ action.circulation%ROWTYPE;
    counter   INTEGER DEFAULT 1;
BEGIN

    RAISE NOTICE 
        'Migrating circ history for % users.  This might take a while...',
        (SELECT COUNT(DISTINCT(au.id)) FROM actor.usr au
            JOIN actor.usr_setting aus ON (aus.usr = au.id)
            WHERE NOT au.deleted AND 
                aus.name ~ '^history.circ.retention_');

    FOR cur_usr IN 
        SELECT DISTINCT(au.id)
            FROM actor.usr au 
            JOIN actor.usr_setting aus ON (aus.usr = au.id)
            WHERE NOT au.deleted AND 
                aus.name ~ '^history.circ.retention_' LOOP

        FOR cur_circ IN SELECT * FROM action.usr_visible_circs(cur_usr) LOOP

            PERFORM TRUE FROM asset.copy WHERE id = cur_circ.target_copy;

            -- Avoid inserting a circ history row when the circulated
            -- item has been (forcibly) removed from the database.
            IF NOT FOUND THEN
                CONTINUE;
            END IF;

            -- Find the last circ in the circ chain.
            SELECT INTO last_circ * 
                FROM action.circ_chain(cur_circ.id) 
                ORDER BY xact_start DESC LIMIT 1;

            -- Create the history row.
            -- It's OK if last_circ = cur_circ
            INSERT INTO action.usr_circ_history 
                (usr, xact_start, target_copy, 
                    due_date, checkin_time, source_circ)
            VALUES (
                cur_circ.usr, 
                cur_circ.xact_start, 
                cur_circ.target_copy, 
                last_circ.due_date, 
                last_circ.checkin_time,
                cur_circ.id
            );

            -- useful for alleviating administrator anxiety.
            IF counter % 10000 = 0 THEN
                RAISE NOTICE 'Migrated history for % total users', counter;
            END IF;

            counter := counter + 1;

        END LOOP;
    END LOOP;

END $FUNK$;

DROP FUNCTION IF EXISTS action.usr_visible_circs (INTEGER);
DROP FUNCTION IF EXISTS action.usr_visible_circ_copies (INTEGER);

-- remove user retention age checks
CREATE OR REPLACE FUNCTION action.purge_circulations () RETURNS INT AS $func$
DECLARE
    org_keep_age    INTERVAL;
    org_use_last    BOOL = false;
    org_age_is_min  BOOL = false;
    org_keep_count  INT;

    keep_age        INTERVAL;

    target_acp      RECORD;
    circ_chain_head action.circulation%ROWTYPE;
    circ_chain_tail action.circulation%ROWTYPE;

    count_purged    INT;
    num_incomplete  INT;

    last_finished   TIMESTAMP WITH TIME ZONE;
BEGIN

    count_purged := 0;

    SELECT value::INTERVAL INTO org_keep_age FROM config.global_flag WHERE name = 'history.circ.retention_age' AND enabled;

    SELECT value::INT INTO org_keep_count FROM config.global_flag WHERE name = 'history.circ.retention_count' AND enabled;
    IF org_keep_count IS NULL THEN
        RETURN count_purged; -- Gimme a count to keep, or I keep them all, forever
    END IF;

    SELECT enabled INTO org_use_last FROM config.global_flag WHERE name = 'history.circ.retention_uses_last_finished';
    SELECT enabled INTO org_age_is_min FROM config.global_flag WHERE name = 'history.circ.retention_age_is_min';

    -- First, find copies with more than keep_count non-renewal circs
    FOR target_acp IN
        SELECT  target_copy,
                COUNT(*) AS total_real_circs
          FROM  action.circulation
          WHERE parent_circ IS NULL
                AND xact_finish IS NOT NULL
          GROUP BY target_copy
          HAVING COUNT(*) > org_keep_count
    LOOP
        -- And, for those, select circs that are finished and older than keep_age
        FOR circ_chain_head IN
            -- For reference, the subquery uses a window function to order the circs newest to oldest and number them
            -- The outer query then uses that information to skip the most recent set the library wants to keep
            -- End result is we don't care what order they come out in, as they are all potentials for deletion.
            SELECT ac.* FROM action.circulation ac JOIN (
              SELECT  rank() OVER (ORDER BY xact_start DESC), ac.id
                FROM  action.circulation ac
                WHERE ac.target_copy = target_acp.target_copy
                  AND ac.parent_circ IS NULL
                ORDER BY ac.xact_start ) ranked USING (id)
                WHERE ranked.rank > org_keep_count
        LOOP

            SELECT * INTO circ_chain_tail FROM action.circ_chain(circ_chain_head.id) ORDER BY xact_start DESC LIMIT 1;
            SELECT COUNT(CASE WHEN xact_finish IS NULL THEN 1 ELSE NULL END), MAX(xact_finish) INTO num_incomplete, last_finished FROM action.circ_chain(circ_chain_head.id);
            CONTINUE WHEN circ_chain_tail.xact_finish IS NULL OR num_incomplete > 0;

            IF NOT org_use_last THEN
                last_finished := circ_chain_tail.xact_finish;
            END IF;

            keep_age := COALESCE( org_keep_age, '2000 years'::INTERVAL );

            IF org_age_is_min THEN
                keep_age := GREATEST( keep_age, org_keep_age );
            END IF;

            CONTINUE WHEN AGE(NOW(), last_finished) < keep_age;

            -- We've passed the purging tests, purge the circ chain starting at the end
            -- A trigger should auto-purge the rest of the chain.
            DELETE FROM action.circulation WHERE id = circ_chain_tail.id;

            count_purged := count_purged + 1;

        END LOOP;
    END LOOP;

    return count_purged;
END;
$func$ LANGUAGE PLPGSQL;

-- delete circ history rows when a user is purged.
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
    DELETE FROM action.usr_circ_history WHERE usr = src_usr;

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



COMMIT;

