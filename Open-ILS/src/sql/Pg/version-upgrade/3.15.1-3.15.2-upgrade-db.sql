--Upgrade Script for 3.15.1 to 3.15.2
\set eg_version '''3.15.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.15.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1471', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.oils_xpath_string(text, text, text, anyarray) RETURNS text
AS $F$
    SELECT  ARRAY_TO_STRING(
                oils_xpath(
                    $1 ||
                        CASE WHEN $1 ~ $re$/[^/[]*@[^]]+$$re$ OR $1 ~ $re$\)$$re$ THEN '' ELSE '//text()' END,
                    $2,
                    $4
                ),
                $3
            );
$F$ LANGUAGE SQL IMMUTABLE;



SELECT evergreen.upgrade_deps_block_check('1472', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.coded_value_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.coded_value_map',
        'Grid Config: eg.grid.admin.config.coded_value_map',
        'cwst', 'label'
    )
);

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
