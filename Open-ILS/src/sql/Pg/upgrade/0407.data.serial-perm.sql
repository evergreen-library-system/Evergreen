BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0407'); -- senator

INSERT INTO permission.perm_list (id, code, description) VALUES
    (481, 'ADMIN_SERIAL_CAPTION_PATTERN', oils_i18n_gettext(481, 'Create/update/delete serial caption and pattern objects', 'ppl', 'description')),
    (482, 'ADMIN_SERIAL_DISTRIBUTION', oils_i18n_gettext(482, 'Create/update/delete serial distribution objects', 'ppl', 'description')),
    (483, 'ADMIN_SERIAL_STREAM', oils_i18n_gettext(483, 'Create/update/delete serial stream objects', 'ppl', 'description'));

COMMIT;

