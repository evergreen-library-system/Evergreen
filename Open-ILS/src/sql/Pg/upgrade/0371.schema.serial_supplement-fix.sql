-- If these two fail, they're already renamed (DB built after 0352), so
-- we're good.
ALTER SEQUENCE serial.sup_summary_id_seq RENAME TO supplement_summary_id_seq;
ALTER SEQUENCE serial.bib_summary_id_seq RENAME TO basic_summary_id_seq;

BEGIN;  -- but we still need to consume an upgrade number :-/

INSERT INTO config.upgrade_log (version) VALUES ('0371');   -- senator

COMMIT;
