BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0409'); -- senator

INSERT INTO permission.perm_list (id, code, description) VALUES
    (484, 'RECEIVE_SERIAL', oils_i18n_gettext(484, 'Receive serial items', 'ppl', 'description'));

COMMIT;
