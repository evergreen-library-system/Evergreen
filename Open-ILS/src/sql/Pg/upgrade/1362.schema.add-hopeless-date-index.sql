BEGIN;

SELECT evergreen.upgrade_deps_block_check('1362', :eg_version);

CREATE INDEX hold_request_hopeless_date_idx ON action.hold_request (hopeless_date);

COMMIT;

ANALYZE action.hold_request;
