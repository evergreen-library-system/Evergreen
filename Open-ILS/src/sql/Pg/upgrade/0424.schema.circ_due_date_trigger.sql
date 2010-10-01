BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0424'); -- dbs

DROP TRIGGER push_due_date_tgr ON action.circulation;

CREATE TRIGGER push_due_date_tgr BEFORE INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.push_circ_due_time();

COMMIT;
