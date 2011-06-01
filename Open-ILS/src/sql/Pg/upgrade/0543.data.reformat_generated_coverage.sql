BEGIN;

-- Reformat generated_coverage to be JSON arrays rather than simple comma-
-- separated lists.

-- This upgrade script is technically imperfect, but should do the right thing
-- in 99.9% of cases, and any mistakes will be self-healing as more serials
-- activity happens

INSERT INTO config.upgrade_log (version) VALUES ('0543'); -- dbwells

UPDATE serial.basic_summary SET generated_coverage = '["' || regexp_replace(regexp_replace(generated_coverage, '"', E'\\"', 'g'), ', ', '","', 'g') || '"]' WHERE generated_coverage <> '';

UPDATE serial.supplement_summary SET generated_coverage = '["' || regexp_replace(regexp_replace(generated_coverage, '"', E'\\"', 'g'), ', ', '","', 'g') || '"]' WHERE generated_coverage <> '';

UPDATE serial.index_summary SET generated_coverage = '["' || regexp_replace(regexp_replace(generated_coverage, '"', E'\\"', 'g'), ', ', '","', 'g') || '"]' WHERE generated_coverage <> '';

COMMIT;
