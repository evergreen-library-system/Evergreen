BEGIN;

SELECT evergreen.upgrade_deps_block_check('0854', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    553,
    'UPDATE_ORG_UNIT_SETTING.circ.min_item_price',
    oils_i18n_gettext(
        553,
        'UPDATE_ORG_UNIT_SETTING.circ.min_item_price',
        'ppl',
        'description'
    )
), (
	554,
    'UPDATE_ORG_UNIT_SETTING.circ.max_item_price',
    oils_i18n_gettext(
        554,
        'UPDATE_ORG_UNIT_SETTING.circ.max_item_price',
        'ppl',
        'description'
    )
);

INSERT into config.org_unit_setting_type
    ( name, grp, label, description, datatype, fm_class )
VALUES (
    'circ.min_item_price',
	'finance',
    oils_i18n_gettext(
        'circ.min_item_price',
        'Minimum Item Price',
        'coust', 'label'),
    oils_i18n_gettext(
        'circ.min_item_price',
        'When charging for lost items, charge this amount as a minimum.',
        'coust', 'description'),
    'currency',
    NULL
), (
    'circ.max_item_price',
    'finance',
    oils_i18n_gettext(
        'circ.max_item_price',
        'Maximum Item Price',
        'coust', 'label'),
    oils_i18n_gettext(
        'circ.max_item_price',
        'When charging for lost items, limit the charge to this as a maximum.',
        'coust', 'description'),
    'currency',
    NULL
);

COMMIT;
