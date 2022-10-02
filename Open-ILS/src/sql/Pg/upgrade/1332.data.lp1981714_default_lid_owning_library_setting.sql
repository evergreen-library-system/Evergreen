BEGIN;

SELECT evergreen.upgrade_deps_block_check('1332', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

( 'acq.default_owning_lib_for_auto_lids_strategy', 'acq',
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids_strategy',
        'How to set default owning library for auto-created line item items',
        'coust', 'label'),
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids_strategy',
        'Stategy to use to set default owning library to set when line item items are auto-created because the provider''s default copy count has been set. Valid values are "workstation" to use the workstation library, "blank" to leave it blank, and "use_setting" to use the "Default owning library for auto-created line item items" setting. If not set, the workstation library will be used.',
        'coust', 'description'),
    'string', null)
,( 'acq.default_owning_lib_for_auto_lids', 'acq',
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids',
        'Default owning library for auto-created line item items',
        'coust', 'label'),
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids',
        'The default owning library to set when line item items are auto-created because the provider''s default copy count has been set. This applies if the "How to set default owning library for auto-created line item items" setting is set to "use_setting".',
        'coust', 'description'),
    'link', 'aou')
;

COMMIT;
