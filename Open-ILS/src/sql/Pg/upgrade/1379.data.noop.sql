BEGIN;

SELECT evergreen.upgrade_deps_block_check('1379', :eg_version);

-- this intentionally does nothing other than inserting the
-- database revision stamp; the only substantive use of 1379
-- is in rel_3_10, but it's important to ensure that anybody
-- applying the individual DB updates doesn't accidentally
-- apply the 1379 change to a 3.11 or later system

COMMIT;

