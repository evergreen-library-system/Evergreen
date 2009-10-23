BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0051');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.uncancel.reset_request_time',
        'Holds: Reset request time on un-cancel',
        'When a holds is uncanceled, reset the request time to push it to the end of the queue',
        'bool'
    );

COMMIT;
