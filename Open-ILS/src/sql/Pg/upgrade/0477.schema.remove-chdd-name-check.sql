BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0477'); -- gmcharlt

ALTER TABLE config.hard_due_date DROP CONSTRAINT hard_due_date_name_check;

COMMIT;
