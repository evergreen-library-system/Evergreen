BEGIN;

SELECT evergreen.upgrade_deps_block_check('1285', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.primary_item_value_field',
        'circ',
        oils_i18n_gettext(
            'circ.primary_item_value_field',
            'Use Item Price or Cost as Primary Item Value',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.primary_item_value_field',
            'Expects "price" or "cost" and defaults to price.  This refers to the corresponding field on the item record and gets used in such contexts as notices, max fine values when using item price caps (setting or fine rules), and long overdue, damaged, and lost billings.',
            'coust',
            'description'
        ),
        'string'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.secondary_item_value_field',
        'circ',
        oils_i18n_gettext(
            'circ.secondary_item_value_field',
            'Use Item Price or Cost as Backup Item Value',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.secondary_item_value_field',
            'Expects "price" or "cost", but defaults to neither.  This refers to the corresponding field on the item record and is used as a second-pass fall-through value when determining an item value.  If needed, Evergreen will still look at the "Default Item Price" setting as a final fallback.',
            'coust',
            'description'
        ),
        'string'
    );

COMMIT;
