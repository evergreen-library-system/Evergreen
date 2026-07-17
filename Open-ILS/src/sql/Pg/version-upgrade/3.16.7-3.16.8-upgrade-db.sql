--Upgrade Script for 3.16.7 to 3.16.8
\set eg_version '''3.16.8'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.16.8', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1522', :eg_version);

UPDATE openapi.endpoint_response
SET schema_type = 'string'
WHERE endpoint = 'logoutUser'
AND content_type = 'application/json';

COMMIT;
