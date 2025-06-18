--Upgrade Script for 3.14.6 to 3.14.7
\set eg_version '''3.14.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.14.7', :eg_version);

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


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
