BEGIN;

SELECT evergreen.upgrade_deps_block_check('1023', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
(
    'cat.default_merge_profile', 'cat',
    oils_i18n_gettext(
        'cat.default_merge_profile',
        'Default Merge Profile (Z39.50 and Record Buckets)',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'cat.default_merge_profile',
        'Default merge profile to use during Z39.50 imports and record bucket merges',
        'coust',
        'description'
    ),
    'link',
    'vmp'
);

COMMIT;
