BEGIN;

SELECT evergreen.upgrade_deps_block_check('1033', :eg_version);

-- correctly turn off browsing for subjectd|geograhic and
-- subject|temporal now that the *_browse versions exist. This is
-- a no-op in a database that was started at version 2.12.0.
UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'geographic'
AND browse_field
AND id = 11;
UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'temporal'
AND browse_field
AND id = 13;

select b.tag, idx.name
from authority.control_set_bib_field b
join authority.control_set_bib_field_metabib_field_map map on (b.id = map.bib_field)
join config.metabib_field idx on (map.metabib_field = idx.id)
order by b.tag;

-- and fix bib field mapping if necessasry
UPDATE authority.control_set_bib_field_metabib_field_map map
SET metabib_field = cmf.id
FROM config.metabib_field cmf
WHERE cmf.field_class = 'subject' AND cmf.name= 'temporal_browse'
AND   map.bib_field IN (
    SELECT b.id
    FROM authority.control_set_bib_field b
    JOIN authority.control_set_authority_field a
    ON (b.authority_field = a.id)
    AND a.tag = '148'
)
AND   map.metabib_field IN (
    SELECT id
    FROM config.metabib_field
    WHERE field_class = 'subject' AND name = 'geographic_browse'
);
UPDATE authority.control_set_bib_field_metabib_field_map map
SET metabib_field = cmf.id
FROM config.metabib_field cmf
WHERE cmf.field_class = 'subject' AND cmf.name= 'geographic_browse'
AND   map.bib_field IN (
    SELECT b.id
    FROM authority.control_set_bib_field b
    JOIN authority.control_set_authority_field a
    ON (b.authority_field = a.id)
    AND a.tag = '151'
)
AND   map.metabib_field IN (
    SELECT id
    FROM config.metabib_field
    WHERE field_class = 'subject' AND name = 'temporal_browse'
);

\qecho Verify that bib subject fields appear to be mapped to
\qecho to correct browse indexes
SELECT b.id, b.tag, idx.field_class, idx.name
FROM authority.control_set_bib_field b
JOIN authority.control_set_bib_field_metabib_field_map map ON (b.id = map.bib_field)
JOIN config.metabib_field idx ON (map.metabib_field = idx.id)
WHERE tag ~ '^6'
ORDER BY b.tag;

COMMIT;

\qecho This is a browse-only reingest of your bib records. It may take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
\qecho .
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE)
    FROM biblio.record_entry;
