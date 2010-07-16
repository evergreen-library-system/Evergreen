BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0341'); -- gmc

INSERT INTO permission.perm_list (id, code, description) SELECT DISTINCT
    392,
    'COPY_NEEDED_FOR_HOLD.override',
    oils_i18n_gettext(
        392,
        'Allow a user to force renewal of an item that could fulfill a hold request',
        'ppl',
        'description'
    )
FROM permission.perm_list
WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'COPY_NEEDED_FOR_HOLD.override');
-- near as I can tell, COPY_NEEDED_FOR_HOLD.override never existed as seed data but was manually
-- added by a fair number of Evergreen users in the past

COMMIT;
