BEGIN;

SELECT evergreen.upgrade_deps_block_check('1043', :eg_version);

ALTER TABLE action_trigger.event_definition
    ADD COLUMN retention_interval INTERVAL;

CREATE OR REPLACE FUNCTION action_trigger.check_valid_retention_interval() 
    RETURNS TRIGGER AS $_$
BEGIN

    /*
     * 1. Retention intervals are alwyas allowed on active hooks.
     * 2. On passive hooks, retention intervals are only allowed
     *    when the event definition has a max_delay value and the
     *    retention_interval value is greater than the difference 
     *    beteween the delay and max_delay values.
     */ 
    PERFORM TRUE FROM action_trigger.hook 
        WHERE key = NEW.hook AND NOT passive;

    IF FOUND THEN
        RETURN NEW;
    END IF;

    IF NEW.max_delay IS NOT NULL THEN
        IF EXTRACT(EPOCH FROM NEW.retention_interval) > 
            ABS(EXTRACT(EPOCH FROM (NEW.max_delay - NEW.delay))) THEN
            RETURN NEW; -- all good
        ELSE
            RAISE EXCEPTION 'retention_interval is too short';
        END IF;
    ELSE
        RAISE EXCEPTION 'retention_interval requires max_delay';
    END IF;
END;
$_$ LANGUAGE PLPGSQL;

CREATE TRIGGER is_valid_retention_interval 
    BEFORE INSERT OR UPDATE ON action_trigger.event_definition
    FOR EACH ROW WHEN (NEW.retention_interval IS NOT NULL)
    EXECUTE PROCEDURE action_trigger.check_valid_retention_interval();

CREATE OR REPLACE FUNCTION action_trigger.purge_events() RETURNS VOID AS $_$
/**
  * Deleting expired events without simultaneously deleting their outputs
  * creates orphaned outputs.  Deleting their outputs and all of the events 
  * linking back to them, plus any outputs those events link to is messy and 
  * inefficient.  It's simpler to handle them in 2 sweeping steps.
  *
  * 1. Delete expired events.
  * 2. Delete orphaned event outputs.
  *
  * This has the added benefit of removing outputs that may have been
  * orphaned by some other process.  Such outputs are not usuable by
  * the system.
  *
  * This does not guarantee that all events within an event group are
  * purged at the same time.  In such cases, the remaining events will
  * be purged with the next instance of the purge (or soon thereafter).
  * This is another nod toward efficiency over completeness of old 
  * data that's circling the bit bucket anyway.
  */
BEGIN

    DELETE FROM action_trigger.event WHERE id IN (
        SELECT evt.id
        FROM action_trigger.event evt
        JOIN action_trigger.event_definition def ON (def.id = evt.event_def)
        WHERE def.retention_interval IS NOT NULL 
            AND evt.state <> 'pending'
            AND evt.update_time < (NOW() - def.retention_interval)
    );

    WITH linked_outputs AS (
        SELECT templates.id AS id FROM (
            SELECT DISTINCT(template_output) AS id
                FROM action_trigger.event WHERE template_output IS NOT NULL
            UNION
            SELECT DISTINCT(error_output) AS id
                FROM action_trigger.event WHERE error_output IS NOT NULL
            UNION
            SELECT DISTINCT(async_output) AS id
                FROM action_trigger.event WHERE async_output IS NOT NULL
        ) templates
    ) DELETE FROM action_trigger.event_output
        WHERE id NOT IN (SELECT id FROM linked_outputs);

END;
$_$ LANGUAGE PLPGSQL;


/* -- UNDO --

BEGIN;
DROP FUNCTION IF EXISTS action_trigger.purge_events();
DROP TRIGGER IF EXISTS is_valid_retention_interval ON action_trigger.event_definition;
DROP FUNCTION IF EXISTS action_trigger.check_valid_retention_interval();
ALTER TABLE action_trigger.event_definition DROP COLUMN retention_interval;
COMMIT;

*/

COMMIT;

