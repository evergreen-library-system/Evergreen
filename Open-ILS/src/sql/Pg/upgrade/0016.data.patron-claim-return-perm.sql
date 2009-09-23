BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0016');

INSERT INTO permission.perm_list (code, description) VALUES (
    'UPDATE_PATRON_CLAIM_RETURN_COUNT',
    'Allows staff to manually change a patron''s claims returned count'
);

COMMIT;

