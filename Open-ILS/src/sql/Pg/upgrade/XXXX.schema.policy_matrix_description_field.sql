BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE config.hold_matrix_matchpoint
    ADD COLUMN description TEXT;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN description TEXT;

COMMIT;
