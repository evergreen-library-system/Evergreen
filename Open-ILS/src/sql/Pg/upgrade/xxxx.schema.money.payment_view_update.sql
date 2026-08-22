BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

DROP RULE IF EXISTS money_payment_view_update ON money.payment_view;

CREATE OR REPLACE FUNCTION money.payment_view_update()
RETURNS trigger AS $$
BEGIN
    UPDATE money.payment
    SET xact = NEW.xact, payment_ts = NEW.payment_ts,
        voided = NEW.voided, amount = NEW.amount, note = NEW.note
    WHERE id = OLD.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS money_payment_view_update_tgr ON money.payment_view;
CREATE TRIGGER money_payment_view_update_tgr
INSTEAD OF UPDATE ON money.payment_view
FOR EACH ROW EXECUTE FUNCTION money.payment_view_update();

COMMIT;
