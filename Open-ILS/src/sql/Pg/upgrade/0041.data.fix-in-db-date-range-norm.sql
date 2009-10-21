BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0041'); -- miker

UPDATE config.index_normalizer SET param_count = 0 WHERE func = 'split_date_range';

COMMIT;

