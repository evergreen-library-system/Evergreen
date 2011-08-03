BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0589');

DROP TRIGGER IF EXISTS mat_summary_add_tgr ON money.cash_payment;
DROP TRIGGER IF EXISTS mat_summary_upd_tgr ON money.cash_payment;
DROP TRIGGER IF EXISTS mat_summary_del_tgr ON money.cash_payment;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('cash_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('cash_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('cash_payment');
 
DROP TRIGGER IF EXISTS mat_summary_add_tgr ON money.check_payment;
DROP TRIGGER IF EXISTS mat_summary_upd_tgr ON money.check_payment;
DROP TRIGGER IF EXISTS mat_summary_del_tgr ON money.check_payment;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('check_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('check_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('check_payment');

COMMIT;

