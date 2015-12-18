
BEGIN;

-- TODO process to delete history items once the age threshold 
-- history.circ.retention_age is reached?

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version); 

CREATE TABLE action.usr_circ_history (
    id           BIGSERIAL PRIMARY KEY,
    usr          INTEGER NOT NULL REFERENCES actor.usr(id)
                 DEFERRABLE INITIALLY DEFERRED,
    xact_start   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    target_copy  BIGINT NOT NULL REFERENCES asset.copy(id)
                 DEFERRABLE INITIALLY DEFERRED,
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


COMMIT;

