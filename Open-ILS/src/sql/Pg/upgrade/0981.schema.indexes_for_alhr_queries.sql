BEGIN;

SELECT evergreen.upgrade_deps_block_check('0981', :eg_version); 

CREATE INDEX hold_request_copy_capture_time_idx ON action.hold_request (current_copy,capture_time);
CREATE INDEX hold_request_open_captured_shelf_lib_idx ON action.hold_request (current_shelf_lib) WHERE capture_time IS NOT NULL AND fulfillment_time IS NULL AND (pickup_lib <> current_shelf_lib);

COMMIT;
