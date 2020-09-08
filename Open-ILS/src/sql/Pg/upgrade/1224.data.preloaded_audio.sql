BEGIN;

SELECT evergreen.upgrade_deps_block_check('1224', :eg_version);

INSERT INTO config.coded_value_map (id,ctype,code,opac_visible,is_simple,value,search_label) VALUES
(1736,'icon_format','preloadedaudio',TRUE,FALSE,
    oils_i18n_gettext(1736, 'Preloaded Audio', 'ccvm', 'value'),
    oils_i18n_gettext(1736, 'Preloaded Audio', 'ccvm', 'search_label')),
(1737,'search_format','preloadedaudio',TRUE,FALSE,
    oils_i18n_gettext(1737, 'Preloaded Audio', 'ccvm', 'value'),
    oils_i18n_gettext(1737, 'Preloaded Audio', 'ccvm', 'search_label'))
;

INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES
((SELECT id from config.coded_value_map where ctype = 'search_format' AND code = 'preloadedaudio'),'{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"item_form","_val":"q"}}'),
((SELECT id from config.coded_value_map where ctype = 'icon_format' AND code = 'preloadedaudio'),'{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"item_form","_val":"q"}}');


COMMIT;
