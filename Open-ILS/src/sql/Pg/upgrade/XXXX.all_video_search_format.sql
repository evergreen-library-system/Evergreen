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

INSERT INTO config.composite_attr_entry_definition (coded_value, definition)
    SELECT 1738, '{"_attr":"item_type","_val":"g"}'
WHERE NOT EXISTS (
    SELECT 1 FROM config.composite_attr_entry_definition WHERE coded_value = 1738
);

COMMIT;

\qecho
\qecho This is a partial record attribute reingest of your bib records.
\qecho It may take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
SELECT COUNT(metabib.reingest_record_attributes(bre.id))
    FROM biblio.record_entry bre
    JOIN metabib.record_attr_flat mraf ON (bre.id = mraf.id)
    WHERE deleted IS FALSE
    AND attr = 'item_type'
    AND value = 'g';
