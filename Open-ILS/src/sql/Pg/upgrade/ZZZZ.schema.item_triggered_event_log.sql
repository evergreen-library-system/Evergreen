BEGIN;

SELECT evergreen.upgrade_deps_block_check('ZZZZ', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.item.event_grid', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.item.event_grid',
    'Grid Config: item.event_grid',
    'cwst', 'label')
), (
    'eg.grid.patron.event_grid', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.patron.event_grid',
    'Grid Config: patron.event_grid',
    'cwst', 'label')
);

DROP TRIGGER IF EXISTS action_trigger_event_context_item_trig ON action_trigger.event;

-- Create a NULLABLE version of the fake-copy-fkey trigger function.
CREATE OR REPLACE FUNCTION evergreen.fake_fkey_tgr () RETURNS TRIGGER AS $F$
DECLARE
    copy_id BIGINT;
BEGIN
    EXECUTE 'SELECT ($1).' || quote_ident(TG_ARGV[0]) INTO copy_id USING NEW;
    IF copy_id IS NOT NULL THEN
        PERFORM * FROM asset.copy WHERE id = copy_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Key (%.%=%) does not exist in asset.copy', TG_TABLE_SCHEMA, TG_TABLE_NAME, copy_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;


--    context_item_path        TEXT, -- for optimizing action_trigger.event
ALTER TABLE action_trigger.event_definition ADD COLUMN context_item_path TEXT;

--    context_item     BIGINT      REFERENCES asset.copy (id)
ALTER TABLE action_trigger.event ADD COLUMN context_item BIGINT;
CREATE INDEX atev_context_item ON action_trigger.event (context_item);

UPDATE
    action_trigger.event_definition
SET
    context_item_path = 'target_copy'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'circ'
    )
;

UPDATE
    action_trigger.event_definition
SET
    context_item_path = 'current_copy'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'ahr'
    )
;

-- Retroactively setting context_item on existing rows in action_trigger.event:
-- This is not done by default because it'll likely take a long time depending on the Evergreen
-- installation.  You may want to do this out-of-band with the upgrade if you want to do this at all.
--
-- \pset format unaligned
-- \t
-- \o update_action_trigger_events_for_circs.sql
-- SELECT 'UPDATE action_trigger.event e SET context_item = c.target_copy FROM action.circulation cWHERE c.id = e.target AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.circulation c WHERE e.target = c.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'circ')) ORDER BY e.id DESC;
-- \o
-- \o update_action_trigger_events_for_holds.sql
-- SELECT 'UPDATE action_trigger.event e SET context_item = h.current_copy FROM action.hold_request h WHERE h.id = e.target AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.hold_request h WHERE e.target = h.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'ahr')) ORDER BY e.id DESC;
-- \o

COMMIT;

CREATE TRIGGER action_trigger_event_context_item_trig
  AFTER INSERT OR UPDATE ON action_trigger.event
  FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('context_item');

