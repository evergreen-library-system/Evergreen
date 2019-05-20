BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE permission.perm_list 
    SET description = oils_i18n_gettext(
        '608',
        'Allows a user to apply values to workstation settings',
        'ppl', 'description')
    WHERE code = 'APPLY_WORKSTATION_SETTING' and description = 'APPLY_WORKSTATION_SETTING';

COMMIT;
