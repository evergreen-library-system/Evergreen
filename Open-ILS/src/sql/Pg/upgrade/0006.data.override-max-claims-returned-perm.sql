BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0006');

INSERT INTO permission.perm_list VALUES 
    (344,'SET_CIRC_CLAIMS_RETURNED.override', oils_i18n_gettext(344,'Allows staff to override the max claims returned value for a patron', 'ppl', 'description'));

COMMIT;

