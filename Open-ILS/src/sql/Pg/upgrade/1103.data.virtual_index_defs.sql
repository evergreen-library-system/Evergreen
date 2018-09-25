BEGIN;

SELECT evergreen.upgrade_deps_block_check('1103', :eg_version);

INSERT INTO config.metabib_field (id, field_class, name, label, browse_field)
    VALUES (45, 'keyword', 'blob', 'All searchable fields', FALSE);

INSERT INTO config.metabib_field (id, field_class, name, format, weight,
    label, xpath, display_field, search_field, browse_field, facet_field)
VALUES (
    53, 'title', 'maintitle', 'marcxml', 10,
    oils_i18n_gettext(53, 'Main Title', 'cmf', 'label'),
    $$//*[@tag='245']/*[@code='a']$$,
    FALSE, TRUE, FALSE, FALSE
);

INSERT INTO config.metabib_field_virtual_map (real, virtual)
    SELECT  id,
            45
      FROM  config.metabib_field
      WHERE search_field
            AND id NOT IN (15, 45, 38, 40) -- keyword|keyword, self, edition, publisher
            AND id NOT IN (SELECT real FROM config.metabib_field_virtual_map);

UPDATE config.metabib_field SET xpath=$$//mods32:mods/mods32:subject[not(descendant::mods32:geographicCode)]$$ WHERE id = 16;

UPDATE config.metabib_field_virtual_map SET weight = -1 WHERE real = 39;
UPDATE config.metabib_field_virtual_map SET weight = 0 WHERE real = 41;
UPDATE config.metabib_field_virtual_map SET weight = 0 WHERE real = 42;
UPDATE config.metabib_field_virtual_map SET weight = 0 WHERE real = 46;
UPDATE config.metabib_field_virtual_map SET weight = 0 WHERE real = 47;
UPDATE config.metabib_field_virtual_map SET weight = 0 WHERE real = 48;
UPDATE config.metabib_field_virtual_map SET weight = 0 WHERE real = 50;
UPDATE config.metabib_field_virtual_map SET weight = 8 WHERE real = 6;
UPDATE config.metabib_field_virtual_map SET weight = 8 WHERE real = 8;
UPDATE config.metabib_field_virtual_map SET weight = 8 WHERE real = 16;
UPDATE config.metabib_field_virtual_map SET weight = 12 WHERE real = 53;

-- Stemming for genre
INSERT INTO config.metabib_field_ts_map (metabib_field, ts_config)
    SELECT 33, 'english_nostop' WHERE NOT EXISTS (
        SELECT 1 FROM config.metabib_field_ts_map WHERE metabib_field = 33 AND ts_config = 'english_nostop'
    )
;

COMMIT;

\qecho 
\qecho Reingesting all records.  This may take a while. 
\qecho This command can be stopped (control-c) and rerun later if needed: 
\qecho 
\qecho DO $FUNC$
\qecho DECLARE
\qecho     same_marc BOOL;
\qecho BEGIN
\qecho     SELECT INTO same_marc enabled FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';
\qecho     UPDATE config.internal_flag SET enabled = true WHERE name = 'ingest.reingest.force_on_same_marc';
\qecho     UPDATE biblio.record_entry SET id=id WHERE not deleted AND id > 0;
\qecho     UPDATE config.internal_flag SET enabled = same_marc WHERE name = 'ingest.reingest.force_on_same_marc';
\qecho END;
\qecho $FUNC$;

DO $FUNC$
DECLARE
    same_marc BOOL;
BEGIN
    SELECT INTO same_marc enabled FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';
    UPDATE config.internal_flag SET enabled = true WHERE name = 'ingest.reingest.force_on_same_marc';
    UPDATE biblio.record_entry SET id=id WHERE not deleted AND id > 0;
    UPDATE config.internal_flag SET enabled = same_marc WHERE name = 'ingest.reingest.force_on_same_marc';
END;
$FUNC$;

