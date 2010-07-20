BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0345'); --gmc

UPDATE config.z3950_attr SET truncation = 1 WHERE source = 'biblios' AND truncation = 0;

COMMIT;
