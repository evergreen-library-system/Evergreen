BEGIN;

SELECT evergreen.upgrade_deps_block_check('ZZZZ', :eg_version);

UPDATE actor.org_unit_setting
SET name = CASE
    WHEN name = 'lib.ecard_barcode_length' THEN 'vendor.quipu.ecard.barcode_length'
    WHEN name = 'lib.ecard_barcode_calculate_checkdigit' THEN 'vendor.quipu.ecard.calculate_checkdigit'
    WHEN name = 'lib.ecard_patron_profile' THEN 'vendor.quipu.ecard.patron_profile'
    WHEN name = 'lib.ecard_admin_usrname' THEN 'vendor.quipu.ecard.admin_usrname'
    WHEN name = 'lib.ecard_admin_org_unit' THEN 'vendor.quipu.ecard.admin_org_unit'
    WHEN name = 'lib.ecard_quipu_id' THEN 'vendor.quipu.ecard.account_id'
    WHEN name = 'lib.ecard_barcode_prefix' THEN 'vendor.quipu.ecard.barcode_prefix'
    ELSE name
END
WHERE name IN (
    'lib.ecard_barcode_length',
    'lib.ecard_barcode_calculate_checkdigit',
    'lib.ecard_patron_profile',
    'lib.ecard_admin_usrname',
    'lib.ecard_admin_org_unit',
    'lib.ecard_quipu_id',
    'lib.ecard_barcode_prefix'
);


ROLLBACK;
