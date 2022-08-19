BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE action.hold_request 
ADD COLUMN canceled_by INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
ADD COLUMN canceling_ws INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX hold_request_canceled_by_idx ON action.hold_request (canceled_by);
CREATE INDEX hold_request_canceling_ws_idx ON action.hold_request (canceling_ws);

COMMIT;

