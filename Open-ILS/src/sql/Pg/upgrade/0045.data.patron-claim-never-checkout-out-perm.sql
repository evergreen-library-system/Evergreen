BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0045');

INSERT INTO permission.perm_list 
    VALUES (
        349,
        'UPDATE_PATRON_CLAIM_NEVER_CHECKED_OUT_COUNT', 
        oils_i18n_gettext(349,'Allows staff to manually change a patron''s claims never checkout out count', 'ppl', 'description')
    );

COMMIT;

