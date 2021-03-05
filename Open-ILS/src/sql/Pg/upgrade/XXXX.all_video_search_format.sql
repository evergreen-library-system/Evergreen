BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.coded_value_map
    (id, ctype, code, opac_visible, value, search_label)
    SELECT 1738,'search_format','video', true,
    oils_i18n_gettext(1738, 'All Videos', 'ccvm', 'value'),
    oils_i18n_gettext(1738, 'All Videos', 'ccvm', 'search_label')
    WHERE NOT EXISTS (
        SELECT 1 FROM config.coded_value_map WHERE id=1738
        OR value = 'All Videos' OR search_label = 'All Videos'
    );

INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES
    (1738, '{"_attr":"item_type","_val":"g"}');

COMMIT;

\qecho
\qecho This is a record attribute reingest of your bib records.
\qecho It will take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
SELECT COUNT(metabib.reingest_record_attributes(id))
    FROM biblio.record_entry WHERE deleted IS FALSE;