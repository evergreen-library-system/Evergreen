BEGIN;

SELECT evergreen.upgrade_deps_block_check('0764', :eg_version);

UPDATE config.z3950_source
    SET host = 'lx2.loc.gov', port = 210, db = 'LCDB'
    WHERE name = 'loc'
        AND host = 'z3950.loc.gov'
        AND port = 7090
        AND db = 'Voyager';

UPDATE config.z3950_attr
    SET format = 6
    WHERE source = 'loc'
        AND name = 'lccn'
        AND format = 1;

COMMIT;

