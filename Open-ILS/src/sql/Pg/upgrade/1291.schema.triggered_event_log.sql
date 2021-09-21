BEGIN;

SELECT evergreen.upgrade_deps_block_check('1291', :eg_version);

--    context_usr_path        TEXT, -- for optimizing action_trigger.event
--    context_library_path    TEXT, -- '''
--    context_bib_path        TEXT, -- '''
ALTER TABLE action_trigger.event_definition ADD COLUMN context_usr_path TEXT;
ALTER TABLE action_trigger.event_definition ADD COLUMN context_library_path TEXT;
ALTER TABLE action_trigger.event_definition ADD COLUMN context_bib_path TEXT;

--    context_user    INT         REFERENCES actor.usr (id),
--    context_library INT         REFERENCES actor.org_unit (id),
--    context_bib     BIGINT      REFERENCES biblio.record_entry (id)
ALTER TABLE action_trigger.event ADD COLUMN context_user INT REFERENCES actor.usr (id);
ALTER TABLE action_trigger.event ADD COLUMN context_library INT REFERENCES actor.org_unit (id);
ALTER TABLE action_trigger.event ADD COLUMN context_bib BIGINT REFERENCES biblio.record_entry (id);
CREATE INDEX atev_context_user ON action_trigger.event (context_user);
CREATE INDEX atev_context_library ON action_trigger.event (context_library);

UPDATE
    action_trigger.event_definition
SET
    context_usr_path = 'usr',
    context_library_path = 'circ_lib',
    context_bib_path = 'target_copy.call_number.record'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'circ'
    )
;

UPDATE
    action_trigger.event_definition
SET
    context_usr_path = 'usr',
    context_library_path = 'pickup_lib',
    context_bib_path = 'bib_rec'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'ahr'
    )
;

-- Retroactively setting context_user and context_library on existing rows in action_trigger.event:
-- This is not done by default because it'll likely take a long time depending on the Evergreen
-- installation.  You may want to do this out-of-band with the upgrade if you want to do this at all.
--
-- \pset format unaligned
-- \t
-- \o update_action_trigger_events_for_circs.sql
-- SELECT 'UPDATE action_trigger.event e SET context_user = c.usr, context_library = c.circ_lib, context_bib = cn.record FROM action.circulation c, asset.copy i, asset.call_number cn WHERE c.id = e.target AND c.target_copy = i.id AND i.call_number = cn.id AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.circulation c WHERE e.target = c.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'circ')) ORDER BY e.id DESC;
-- \o
-- \o update_action_trigger_events_for_holds.sql
-- SELECT 'UPDATE action_trigger.event e SET context_user = h.usr, context_library = h.pickup_lib, context_bib = r.bib_record FROM action.hold_request h, reporter.hold_request_record r WHERE h.id = e.target AND h.id = r.id AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.hold_request h WHERE e.target = h.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'ahr')) ORDER BY e.id DESC;
-- \o

COMMIT;

