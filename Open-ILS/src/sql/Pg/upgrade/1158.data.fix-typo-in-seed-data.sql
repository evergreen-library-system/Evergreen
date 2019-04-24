BEGIN;

SELECT evergreen.upgrade_deps_block_check('1158', :eg_version);

--LP#1759238: Fix typo in seed data for Physical Description

UPDATE config.metabib_field
    SET label = 'Physical Description'
    WHERE id = 39 AND label = 'Physical Descrption';

COMMIT;
