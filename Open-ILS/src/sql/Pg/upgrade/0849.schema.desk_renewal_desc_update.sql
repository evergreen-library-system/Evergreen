BEGIN;

SELECT evergreen.upgrade_deps_block_check('0849', :eg_version);

UPDATE config.global_flag
    SET label = 'Circ: Use original circulation library on desk renewal instead of the workstation library'
    WHERE name = 'circ.desk_renewal.use_original_circ_lib';

COMMIT;

