BEGIN;

SELECT evergreen.upgrade_deps_block_check('1048', :eg_version);

INSERT into config.org_unit_setting_type (
     name
    ,grp
    ,label
    ,description
    ,datatype
) VALUES ( ----------------------------------------
     'webstaff.cat.label.font.family'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.family'
        ,'Item Print Label Font Family'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.family'
        ,'Set the preferred font family for item print labels. You can specify a list of CSS fonts, separated by commas, in order of preference; the system will use the first font it finds with a matching name. For example, "Arial, Helvetica, serif"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.font.size'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.size'
        ,'Item Print Label Font Size'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.size'
        ,'Set the default font size for item print labels. Please include a unit of measurement that is valid CSS. For example, "12pt" or "16px" or "1em"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.font.weight'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.weight'
        ,'Item Print Label Font Weight'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.weight'
        ,'Set the default font weight for item print labels. Please use the CSS specification for values for font-weight.  For example, "normal", "bold", "bolder", or "lighter"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.left_label.left_margin'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Item Print Label - Left Margin for Left Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Set the default left margin for the leftmost item print Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.right_label.left_margin'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Item Print Label - Left Margin for Right Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Set the default left margin for the rightmost item print label (or in other words, the desired space between the two labels). Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.left_label.height'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Item Print Label - Height for Left Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Set the default height for the leftmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.left_label.width'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Item Print Label - Width for Left Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Set the default width for the leftmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.right_label.height'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Item Print Label - Height for Right Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Set the default height for the rightmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.right_label.width'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Item Print Label - Width for Right Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Set the default width for the rightmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), (
     'webstaff.cat.label.inline_css'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.inline_css'
        ,'Item Print Label - Inline CSS'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.inline_css'
        ,'This setting allows you to inject arbitrary CSS into the item print label template.  For example, ".printlabel { text-transform: uppercase; }"'
        ,'coust'
        ,'description'
    )
    ,'string'
), (
     'webstaff.cat.label.call_number_wrap_filter_height'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_height'
        ,'Item Print Label - Call Number Wrap Filter Height'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_height'
        ,'This setting is used to set the default height (in number of lines) to use for call number wrapping in the left print label.'
        ,'coust'
        ,'description'
    )
    ,'integer'
), (
     'webstaff.cat.label.call_number_wrap_filter_width'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_width'
        ,'Item Print Label - Call Number Wrap Filter Width'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_width'
        ,'This setting is used to set the default width (in number of characters) to use for call number wrapping in the left print label.'
        ,'coust'
        ,'description'
    )
    ,'integer'


);

-- for testing, setting removal:
--DELETE FROM actor.org_unit_setting WHERE name IN (
--     'webstaff.cat.label.font.family'
--    ,'webstaff.cat.label.font.size'
--    ,'webstaff.cat.label.font.weight'
--    ,'webstaff.cat.label.left_label.height'
--    ,'webstaff.cat.label.left_label.width'
--    ,'webstaff.cat.label.left_label.left_margin'
--    ,'webstaff.cat.label.right_label.height'
--    ,'webstaff.cat.label.right_label.width'
--    ,'webstaff.cat.label.right_label.left_margin'
--    ,'webstaff.cat.label.inline_css'
--    ,'webstaff.cat.label.call_number_wrap_filter_height'
--    ,'webstaff.cat.label.call_number_wrap_filter_width'
--);
--DELETE FROM config.org_unit_setting_type_log WHERE field_name IN (
--     'webstaff.cat.label.font.family'
--    ,'webstaff.cat.label.font.size'
--    ,'webstaff.cat.label.font.weight'
--    ,'webstaff.cat.label.left_label.height'
--    ,'webstaff.cat.label.left_label.width'
--    ,'webstaff.cat.label.left_label.left_margin'
--    ,'webstaff.cat.label.right_label.height'
--    ,'webstaff.cat.label.right_label.width'
--    ,'webstaff.cat.label.right_label.left_margin'
--    ,'webstaff.cat.label.inline_css'
--    ,'webstaff.cat.label.call_number_wrap_filter_height'
--    ,'webstaff.cat.label.call_number_wrap_filter_width'
--);
--DELETE FROM config.org_unit_setting_type WHERE name IN (
--     'webstaff.cat.label.font.family'
--    ,'webstaff.cat.label.font.size'
--    ,'webstaff.cat.label.font.weight'
--    ,'webstaff.cat.label.left_label.height'
--    ,'webstaff.cat.label.left_label.width'
--    ,'webstaff.cat.label.left_label.left_margin'
--    ,'webstaff.cat.label.right_label.height'
--    ,'webstaff.cat.label.right_label.width'
--    ,'webstaff.cat.label.right_label.left_margin'
--    ,'webstaff.cat.label.inline_css'
--    ,'webstaff.cat.label.call_number_wrap_filter_height'
--    ,'webstaff.cat.label.call_number_wrap_filter_width'
--);


COMMIT;
