BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXX', :eg_version);

INSERT INTO config.coded_value_map
    (id, ctype, code, value, opac_visible, search_label) VALUES
(712, 'search_format', 'electronic', FALSE,
    oils_i18n_gettext(712, 'Electronic', 'ccvm', 'value'),
    oils_i18n_gettext(712, 'Electronic', 'ccvm', 'search_label'));

INSERT INTO config.composite_attr_entry_definition
    (coded_value, definition) VALUES
(712, '{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"o"}');


COMMIT;

\qecho To use the new electronic search format, it is necessary to do a
\qecho record attribute reingest. For example,
\qecho
\qecho SELECT 'metabib.reingest_record_attributes(' || id || ');'
\qecho biblio.record_entry WHERE NOT DELETED and id > 0;
\qecho
