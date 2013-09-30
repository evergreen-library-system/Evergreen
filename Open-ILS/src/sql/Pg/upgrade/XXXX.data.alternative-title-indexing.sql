BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

UPDATE config.metabib_field
SET
    xpath = $$//mods32:mods/mods32:titleInfo[mods32:title and starts-with(@type,'alternative')]$$,
    browse_sort_xpath = $$*[local-name() != "nonSort"]$$,
    browse_xpath = NULL
WHERE
    field_class = 'title' AND name = 'alternative' ;

COMMIT;

\qecho This is a browse-only reingest of your bib records. It may take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
\qecho .
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE)
    FROM biblio.record_entry;
