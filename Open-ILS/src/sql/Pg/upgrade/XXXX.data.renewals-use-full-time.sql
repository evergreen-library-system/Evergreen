BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN renew_extends_due_date BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN renew_extend_min_interval INTERVAL;

COMMIT;
