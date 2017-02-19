BEGIN;

SELECT evergreen.upgrade_deps_block_check('1026', :eg_version);

INSERT INTO config.metabib_field ( id, field_class, name, label, 
     format, xpath, search_field, browse_field, authority_xpath, joiner ) VALUES
    (34, 'subject', 'topic_browse', oils_i18n_gettext(34, 'Topic Browse', 'cmf', 'label'), 
     'mods32', $$//mods32:mods/mods32:subject[local-name(./*[1]) = "topic"]$$, FALSE, TRUE, '//@xlink:href', ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field ( id, field_class, name, label, 
     format, xpath, search_field, browse_field, authority_xpath, joiner ) VALUES
    (35, 'subject', 'geographic_browse', oils_i18n_gettext(35, 'Geographic Name Browse', 'cmf', 'label'), 
     'mods32', $$//mods32:mods/mods32:subject[local-name(./*[1]) = "geographic"]$$, FALSE, TRUE, '//@xlink:href', ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field ( id, field_class, name, label, 
     format, xpath, search_field, browse_field, authority_xpath, joiner ) VALUES
    (36, 'subject', 'temporal_browse', oils_i18n_gettext(36, 'Temporal Term Browse', 'cmf', 'label'), 
     'mods32', $$//mods32:mods/mods32:subject[local-name(./*[1]) = "temporal"]$$, FALSE, TRUE, '//@xlink:href', ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field_index_norm_map (field,norm)
    SELECT  m.id,
            i.id
      FROM  config.metabib_field m,
        config.index_normalizer i
      WHERE i.func IN ('naco_normalize')
            AND m.id IN (34, 35, 36);

UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'topic'
AND id = 14;
UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'geographic'
AND id = 13;
UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'temporal'
AND id = 11;

UPDATE authority.control_set_bib_field_metabib_field_map
SET metabib_field = 34
WHERE metabib_field = 14;
UPDATE authority.control_set_bib_field_metabib_field_map
SET metabib_field = 35
WHERE metabib_field = 13;
UPDATE authority.control_set_bib_field_metabib_field_map
SET metabib_field = 36
WHERE metabib_field = 11;

COMMIT;

\qecho This is a browse-only reingest of your bib records. It may take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
\qecho .
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE)
    FROM biblio.record_entry;
