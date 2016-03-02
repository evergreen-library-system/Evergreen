BEGIN;

SELECT evergreen.upgrade_deps_block_check('0964', :eg_version);

INSERT INTO config.coded_value_map
    (id, ctype, code, opac_visible, value, search_label) VALUES
(712, 'search_format', 'electronic', FALSE,
    oils_i18n_gettext(712, 'Electronic', 'ccvm', 'value'),
    oils_i18n_gettext(712, 'Electronic', 'ccvm', 'search_label'));

INSERT INTO config.composite_attr_entry_definition
    (coded_value, definition) VALUES
(712, '[{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"o"}]');


COMMIT;

\qecho To use the new electronic search format, it is necessary to do a
\qecho record attribute reingest. Consider generating an SQL script with
\qecho the following queries:
\qecho
\qecho '\\t'
\qecho '\\o /tmp/partial_reingest_bib_recs.sql'
\qecho 'SELECT ''select metabib.reingest_record_attributes('' || id || '');'' FROM biblio.record_entry WHERE NOT DELETED AND id > 0;'
\qecho '\\o'
\qecho '\\t'
\qecho
\qecho
\qecho **** then running it via psql:
\qecho
\qecho
\qecho '\\i /tmp/partial_reingest_bib_recs.sql'
\qecho
