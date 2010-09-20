BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0407'); -- senator

INSERT INTO permission.perm_list (id, code, description) VALUES
    (397, 'ADMIN_SERIAL_CAPTION_PATTERN', oils_i18n_gettext(397, 'Create/update/delete serial caption and pattern objects', 'ppl', 'description')),
    (398, 'ADMIN_SERIAL_SUBSCRIPTION', oils_i18n_gettext(398, 'Create/update/delete serial subscription objects', 'ppl', 'description')),
    (399, 'ADMIN_SERIAL_DISTRIBUTION', oils_i18n_gettext(399, 'Create/update/delete serial distribution objects', 'ppl', 'description')),
    (400, 'ADMIN_SERIAL_STREAM', oils_i18n_gettext(400, 'Create/update/delete serial stream objects', 'ppl', 'description'));

COMMIT;

