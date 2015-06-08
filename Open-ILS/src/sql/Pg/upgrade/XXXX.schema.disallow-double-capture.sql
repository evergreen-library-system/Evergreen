BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE UNIQUE INDEX CONCURRENTLY
    hold_request_capture_protect_idx ON action.hold_request (current_copy)
    WHERE   current_copy IS NOT NULL -- sometimes null in old/bad data
            AND capture_time IS NOT NULL
            AND cancel_time IS NULL
            AND fulfillment_time IS NULL;

COMMIT;

