BEGIN;

SELECT evergreen.upgrade_deps_block_check('1140', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.org_top()
RETURNS actor.org_unit AS $$
    SELECT * FROM actor.org_unit WHERE parent_ou IS NULL LIMIT 1;
$$ LANGUAGE SQL STABLE;

COMMIT:
