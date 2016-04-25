BEGIN;

ALTER TABLE config.hold_matrix_matchpoint
    ADD COLUMN description TEXT;

COMMIT;
