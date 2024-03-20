BEGIN;

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext('acq.default_owning_lib_for_auto_lids_strategy',
        'Strategy to use when setting the default owning library for line item items that are auto-created due to the provider''s default copy count being set. Valid values are "workstation" to use the workstation library, "blank" to leave it blank, and "use_setting" to use the "Default owning library for auto-created line item items" setting. If not set, the workstation library will be used.',
        'coust', 'description')
WHERE name = 'acq.default_owning_lib_for_auto_lids_strategy'
AND description = 'Stategy to use to set default owning library to set when line item items are auto-created because the provider''s default copy count has been set. Valid values are "workstation" to use the workstation library, "blank" to leave it blank, and "use_setting" to use the "Default owning library for auto-created line item items" setting. If not set, the workstation library will be used.';

COMMIT;
