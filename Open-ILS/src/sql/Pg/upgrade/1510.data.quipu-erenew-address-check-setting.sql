BEGIN;

SELECT evergreen.upgrade_deps_block_check('1510', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'vendor.quipu.erenew.num_addresses_required', 'lib',
    oils_i18n_gettext('vendor.quipu.erenew.num_addresses_required',
        'Number of valid addresses needed to offer patron account e-renewal via Quipu',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.erenew.num_addresses_required',
        'Number of valid addresses that a patron record must have in order to offer e-renewal via Quipu. Zero means that the patron record address are not considered; one means that either the mailing or billing/physical address must be set and marked as valid; two means that both the mailing and billing/physical address must be set and marked as valid. Default value is two (2).',
        'coust', 'description'),
    'integer', null);

COMMIT;
