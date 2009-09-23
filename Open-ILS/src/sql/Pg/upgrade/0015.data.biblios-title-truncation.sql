BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0015');

UPDATE config.z3950_attr SET truncation = 1 WHERE source = 'biblios' AND name = 'title';

COMMIT;
