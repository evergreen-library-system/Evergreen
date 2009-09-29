BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0027');

INSERT INTO permission.perm_list VALUES
    (346,'UPDATE_BILL_NOTE', oils_i18n_gettext(346,'Allows staff to edit the note for a bill on a transaction', 'ppl', 'description'));

COMMIT;

