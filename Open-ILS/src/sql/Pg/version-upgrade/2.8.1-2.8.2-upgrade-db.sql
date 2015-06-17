--Upgrade Script for 2.8.1 to 2.8.2
\set eg_version '''2.8.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.2', :eg_version);
-- index serial.record_entry.record


SELECT evergreen.upgrade_deps_block_check('0917', :eg_version);

CREATE INDEX serial_record_entry_record_idx ON serial.record_entry ( record );

-- index authority.simple_heading.record so that reingesting
-- authority records does not require a sequential scan of ash

SELECT evergreen.upgrade_deps_block_check('0918', :eg_version);

CREATE INDEX authority_simple_heading_record_idx ON authority.simple_heading (record);


SELECT evergreen.upgrade_deps_block_check('0919', :eg_version);

ALTER TABLE acq.acq_lineitem_history DROP CONSTRAINT IF EXISTS acq_lineitem_history_queued_record_fkey;


SELECT evergreen.upgrade_deps_block_check('0920', :eg_version);

CREATE UNIQUE INDEX
    hold_request_capture_protect_idx ON action.hold_request (current_copy)
    WHERE   current_copy IS NOT NULL -- sometimes null in old/bad data
            AND capture_time IS NOT NULL
            AND cancel_time IS NULL
            AND fulfillment_time IS NULL;


COMMIT;
