BEGIN;

SELECT evergreen.upgrade_deps_block_check('0877', :eg_version);

-- Don't use Series search field as the browse field
UPDATE config.metabib_field SET
	browse_field = FALSE,
	browse_xpath = NULL,
	browse_sort_xpath = NULL,
	xpath = $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[not(@type="nfi")]$$
WHERE id = 1;

-- Create a new series browse config
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, search_field, authority_xpath, browse_field, browse_sort_xpath ) VALUES
    (32, 'series', 'browse', oils_i18n_gettext(32, 'Series Title (Browse)', 'cmf', 'label'), 'mods32', $$//mods32:mods/mods32:relatedItem[@type="series"]/mods32:titleInfo[@type="nfi"]$$, FALSE, '//@xlink:href', TRUE, $$*[local-name() != "nonSort"]$$ );

COMMIT;

\qecho This is a full field-entry reingest of your bib records.
\qecho It will take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
\qecho .
SELECT COUNT(metabib.reingest_metabib_field_entries(id))
    FROM biblio.record_entry WHERE deleted IS FALSE;
