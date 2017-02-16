--Upgrade Script for 2.11.2 to 2.11.3
\set eg_version '''2.11.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1012', :eg_version);
UPDATE vandelay.merge_profile
SET preserve_spec = '901c',
    replace_spec = NULL
WHERE id = 2
AND   name = oils_i18n_gettext(2, 'Full Overlay', 'vmp', 'name')
AND   preserve_spec IS NULL
AND   add_spec IS NULL
AND   strip_spec IS NULL
AND   replace_spec = '901c';


SELECT evergreen.upgrade_deps_block_check('1013', :eg_version); -- csharp/miker/gmcharlt

CREATE INDEX actor_usr_usrname_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(usrname));



SELECT evergreen.upgrade_deps_block_check('1018', :eg_version);

UPDATE config.org_unit_setting_type
    SET view_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'VIEW_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor.stripe%' AND view_perm IS NULL;

UPDATE config.org_unit_setting_type
    SET update_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'ADMIN_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor.stripe%' AND update_perm IS NULL;

COMMIT;
