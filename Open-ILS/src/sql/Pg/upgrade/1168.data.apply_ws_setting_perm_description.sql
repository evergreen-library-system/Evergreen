BEGIN;

SELECT evergreen.upgrade_deps_block_check('1168', :eg_version); -- csharp/khuckins/gmcharlt

UPDATE permission.perm_list 
    SET description = oils_i18n_gettext(
        '608',
        'Allows a user to apply values to workstation settings',
        'ppl', 'description')
    WHERE code = 'APPLY_WORKSTATION_SETTING' and description = 'APPLY_WORKSTATION_SETTING';

COMMIT;
