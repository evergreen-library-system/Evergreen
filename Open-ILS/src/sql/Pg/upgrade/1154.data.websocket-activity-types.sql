BEGIN;

SELECT evergreen.upgrade_deps_block_check('1154', :eg_version);

INSERT INTO config.usr_activity_type 
    (id, ewhat, ehow, egroup, enabled, transient, label)
VALUES (
    25, 'login', 'ws-translator-v1', 'authen', TRUE, TRUE,
    oils_i18n_gettext(25, 'Login via Websocket V1', 'cuat', 'label')
), (
    26, 'login', 'ws-translator-v2', 'authen', TRUE, TRUE,
    oils_i18n_gettext(26, 'Login via Websocket V2', 'cuat', 'label')
), (
    27, 'verify', 'ws-translator-v1', 'authz', TRUE, TRUE,
    oils_i18n_gettext(27, 'Verification via Websocket v1', 'cuat', 'label')
), (
    28, 'verify', 'ws-translator-v2', 'authz', TRUE, TRUE,
    oils_i18n_gettext(28, 'Verifiation via Websocket V2', 'cuat', 'label')
), (
    29, 'login', NULL, 'authen', TRUE, TRUE,
    oils_i18n_gettext(29, 'Generic Login', 'cuat', 'label')
), (
    30, 'verify', NULL, 'authz', TRUE, TRUE,
    oils_i18n_gettext(30, 'Generic Verify', 'cuat', 'label')
);


COMMIT;
