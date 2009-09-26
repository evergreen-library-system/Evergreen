
-- Populate xact_type column in the materialized version of billable_xact_summary

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0025');

CREATE OR REPLACE FUNCTION money.mat_summary_create () RETURNS TRIGGER AS $$
BEGIN
	INSERT INTO money.materialized_billable_xact_summary (id, usr, xact_start, xact_finish, total_paid, total_owed, balance_owed, xact_type)
		VALUES ( NEW.id, NEW.usr, NEW.xact_start, NEW.xact_finish, 0.0, 0.0, 0.0, TG_ARGV[0]);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

 
DROP TRIGGER mat_summary_create_tgr ON action.circulation;
CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('circulation');
 
DROP TRIGGER mat_summary_create_tgr ON money.grocery;
CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('grocery');

COMMIT;

