BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0463'); -- dbs

UPDATE config.global_flag
    SET enabled = TRUE
    WHERE name IN ('cat.bib.use_id_for_tcn', 'cat.maintain_control_numbers')
;

COMMIT;
