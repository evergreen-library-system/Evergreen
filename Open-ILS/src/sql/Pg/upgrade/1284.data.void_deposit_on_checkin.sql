BEGIN;

SELECT evergreen.upgrade_deps_block_check('1284', :eg_version); -- blake / terranm / jboyer

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.void_item_deposit', 'circ',
    oils_i18n_gettext('circ.void_item_deposit',
        'Void item deposit fee on checkin',
        'coust', 'label'),
    oils_i18n_gettext('circ.void_item_deposit',
        'If a deposit was charged when checking out an item, void it when the item is returned',
        'coust', 'description'),
    'bool', null);

COMMIT;

