BEGIN;

SELECT evergreen.upgrade_deps_block_check('1522', :eg_version);

UPDATE openapi.endpoint_response
SET schema_type = 'string'
WHERE endpoint = 'logoutUser'
AND content_type = 'application/json';

COMMIT;
