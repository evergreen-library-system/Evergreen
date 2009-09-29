BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0016');

INSERT INTO permission.perm_list VALUES 
    (345,'UPDATE_PATRON_CLAIM_RETURN_COUNT', oils_i18n_gettext(345,'Allows staff to manually change a patron''s claims returned count', 'ppl', 'description'));

COMMIT;

