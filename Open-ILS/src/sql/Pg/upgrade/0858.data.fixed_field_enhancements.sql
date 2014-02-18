BEGIN;

SELECT evergreen.upgrade_deps_block_check('0858', :eg_version);

-- Fix faulty seed data. Otherwise for ptype 'f' we have subfield 'e'
-- overlapping subfield 'd'
UPDATE config.marc21_physical_characteristic_subfield_map
    SET start_pos = 5
    WHERE ptype_key = 'f' AND subfield = 'e';

COMMIT;
