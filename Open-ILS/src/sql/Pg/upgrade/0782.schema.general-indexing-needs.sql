
-- No transaction needed. This can be run on a live, production server.
SELECT evergreen.upgrade_deps_block_check('0782', :eg_version);

-- On a heavily used system, user activity lookup is painful.  This is used
-- on the patron display in the staff client.
--
-- Measured speed increase: ~2s -> .01s
CREATE INDEX CONCURRENTLY usr_activity_usr_idx on actor.usr_activity (usr);

-- Finding open holds, often as a subquery within larger hold-related logic,
-- can be sped up with the following.
--
-- Measured speed increase: ~3s -> .02s
CREATE INDEX CONCURRENTLY hold_request_open_idx on action.hold_request (id) where cancel_time IS NULL AND fulfillment_time IS NULL;

-- Hold queue position is a particularly difficult thing to calculate
-- efficiently.  Recent changes in the query structure now allow some
-- optimization via indexing.  These do that.
--
-- Measured speed increase: ~6s -> ~0.4s
CREATE INDEX CONCURRENTLY cp_available_by_circ_lib_idx on asset.copy (circ_lib) where status IN (0,7);
CREATE INDEX CONCURRENTLY hold_request_current_copy_before_cap_idx on action.hold_request (current_copy) where capture_time IS NULL AND cancel_time IS NULL;

-- After heavy use, fetching EDI messages becomes time consuming.  The following
-- index addresses that for large-data environments.
-- 
-- Measured speed increase: ~3s -> .1s
CREATE INDEX CONCURRENTLY edi_message_account_status_idx on acq.edi_message (account,status);

-- After heavy use, fetching POs becomes time consuming.  The following
-- index addresses that for large-data environments.
-- 
-- Measured speed increase: ~1.5s -> .1s
CREATE INDEX CONCURRENTLY edi_message_po_idx on acq.edi_message (purchase_order);

-- Related to EDI messages, fetching of certain A/T events benefit from specific
-- indexing.  This index is more general than necessary for the observed query
-- but ends up speeding several other (already relatively fast) queries.
--
-- Measured speed increase: ~2s -> .06s
CREATE INDEX CONCURRENTLY atev_def_state on action_trigger.event (event_def,state);

-- Retrieval of hold transit by hold id (for transit completion or cancelation)
-- is slow in some query formulations.
--
-- Measured speed increase: ~.5s -> .1s
CREATE INDEX CONCURRENTLY hold_transit_copy_hold_idx on action.hold_transit_copy (hold);

