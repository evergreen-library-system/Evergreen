--Upgrade Script for 3.17.1 to 3.17.2
\set eg_version '''3.17.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.17.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1522', :eg_version);

UPDATE openapi.endpoint_response
SET schema_type = 'string'
WHERE endpoint = 'logoutUser'
AND content_type = 'application/json';


SELECT evergreen.upgrade_deps_block_check('1523', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.circ.patron.nav.collapse', 'circ', 'bool',
    oils_i18n_gettext(
        'eg.circ.patron.nav.collapse',
        'Collapse Patron Navigation Display',
        'cwst', 'label'
    )
);

COMMIT;
