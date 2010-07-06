BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0325');

ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_call_number_fkey FOREIGN KEY (call_number) REFERENCES asset.call_number (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.in_house_use DROP CONSTRAINT in_house_use_item_fkey;
ALTER TABLE action.circulation DROP CONSTRAINT action_circulation_target_copy_fkey;
ALTER TABLE action.hold_request DROP CONSTRAINT hold_request_current_copy_fkey;
ALTER TABLE action.hold_request DROP CONSTRAINT hold_request_hold_type_check;
ALTER TABLE action.transit_copy DROP CONSTRAINT transit_copy_target_copy_fkey;
ALTER TABLE action.hold_transit_copy DROP CONSTRAINT ahtc_tc_fkey;

ALTER TABLE asset.stat_cat_entry_copy_map DROP CONSTRAINT a_sc_oc_fkey;
ALTER TABLE acq.lineitem_detail DROP CONSTRAINT lineitem_detail_eg_copy_id_fkey;

COMMIT;

-- This is optional, might fail, that's ok
ALTER TABLE extend_reporter.legacy_circ_count DROP CONSTRAINT legacy_circ_count_id_fkey;

