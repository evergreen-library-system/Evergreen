BEGIN;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN description TEXT;

COMMIT;
