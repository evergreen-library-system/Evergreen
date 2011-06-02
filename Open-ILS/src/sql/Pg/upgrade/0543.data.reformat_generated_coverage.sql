BEGIN;

-- Reformat generated_coverage to be JSON arrays rather than simple comma-
-- separated lists.

-- This upgrade script is technically imperfect, but should do the right thing
-- in 99.9% of cases, and any mistakes will be self-healing as more serials
-- activity happens

SELECT evergreen.upgrade_deps_block_check('0543', :eg_version); -- dbwells

UPDATE serial.basic_summary SET generated_coverage = '["' || regexp_replace(regexp_replace(generated_coverage, '"', E'\\"', 'g'), ', ', '","', 'g') || '"]' WHERE generated_coverage <> '';

UPDATE serial.supplement_summary SET generated_coverage = '["' || regexp_replace(regexp_replace(generated_coverage, '"', E'\\"', 'g'), ', ', '","', 'g') || '"]' WHERE generated_coverage <> '';

UPDATE serial.index_summary SET generated_coverage = '["' || regexp_replace(regexp_replace(generated_coverage, '"', E'\\"', 'g'), ', ', '","', 'g') || '"]' WHERE generated_coverage <> '';

COMMIT;
