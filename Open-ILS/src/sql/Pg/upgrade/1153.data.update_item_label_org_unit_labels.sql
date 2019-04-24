BEGIN;

SELECT evergreen.upgrade_deps_block_check('1153', :eg_version);

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Item Print Label - Left Margin for Spine Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Set the default left margin for the item print Spine Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.left_label.left_margin';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Item Print Label - Left Margin for Pocket Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Set the default left margin for the item print Pocket Label (or in other words, the desired space between the two labels). Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.right_label.left_margin';


UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Item Print Label - Height for Spine Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Set the default height for the item print Spine Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.left_label.height';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Item Print Label - Width for Spine Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Set the default width for the item print Spine Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.left_label.width';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Item Print Label - Height for Pocket Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Set the default height for the item print Pocket Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.right_label.height';

UPDATE config.org_unit_setting_type
SET label = oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Item Print Label - Width for Pocket Label'
        ,'coust'
        ,'label'
    ),
     description = oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Set the default width for the item print Pocket Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
WHERE NAME = 'webstaff.cat.label.right_label.width';

COMMIT;
