BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0006');

INSERT INTO permission.perm_list (code, description) VALUES (
    'SET_CIRC_CLAIMS_RETURNED.override',
    'Allows staff to override the max claims returned value for a patron'
);

COMMIT;

