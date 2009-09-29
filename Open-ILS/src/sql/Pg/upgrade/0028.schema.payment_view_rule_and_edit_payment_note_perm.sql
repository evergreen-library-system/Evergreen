BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0028');

INSERT INTO permission.perm_list VALUES
    (347,'UPDATE_PAYMENT_NOTE', oils_i18n_gettext(346,'Allows staff to edit the note for a payment on a transaction', 'ppl', 'description'));

CREATE RULE money_payment_view_update AS ON UPDATE TO money.payment_view DO INSTEAD 
    UPDATE money.payment SET xact = NEW.xact, payment_ts = NEW.payment_ts, voided = NEW.voided, amount = NEW.amount, note = NEW.note WHERE id = NEW.id;

COMMIT;

