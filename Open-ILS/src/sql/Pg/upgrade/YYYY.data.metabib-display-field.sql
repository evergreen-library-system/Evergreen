
BEGIN;

INSERT INTO config.internal_flag (name, enabled) 
    VALUES ('ingest.skip_display_indexing', FALSE);

-- Adds seed data to replace (for now) values from the 'mvr' class

INSERT INTO config.metabib_field (id, field_class, name, format,
    display_field, search_field, browse_field, label, xpath) 
VALUES
    (37, 'title', 'display|title', 'mods32', TRUE, FALSE, FALSE,
        oils_i18n_gettext(37, 'Title', 'cmf', 'label'),
        '//mods32:mods/mods32:titleNonfiling[mods32:title and not (@type)]'),
    (38, 'author', 'display|author', 'mods32', TRUE, FALSE, FALSE,
        oils_i18n_gettext(38, 'Author', 'cmf', 'label'),
        $$//mods32:mods/mods32:name[@type='personal' and mods32:role/mods32:roleTerm[text()='creator']]$$),
    (39, 'subject', 'display|subject', 'mods32', TRUE, FALSE, FALSE,
        oils_i18n_gettext(39, 'Subject', 'cmf', 'label'),
        '//mods32:mods/mods32:subject'),
    (40, 'subject', 'display|topic_subject', 'mods32', TRUE, FALSE, FALSE,
        oils_i18n_gettext(40, 'Subject', 'cmf', 'label'),
        '//mods32:mods/mods32:subject/mods32:topic')
;

INSERT INTO config.display_field_map (name, field, multi) VALUES
    ('title', 37, FALSE),
    ('author', 38, FALSE),
    ('subject', 39, TRUE),
    ('topic_subject', 40, TRUE)
;

COMMIT;

-- REINGEST DISPLAY ENTRIES

BEGIN;
UPDATE config.internal_flag SET enabled = TRUE WHERE name IN (
'ingest.assume_inserts_only','ingest.disable_authority_auto_update','ingest.disable_authority_linking','ingest.disable_located_uri','ingest.disable_metabib_field_entry','ingest.disable_metabib_full_rec','ingest.disable_metabib_rec_descriptor','ingest.metarecord_mapping.preserve_on_delete','ingest.metarecord_mapping.skip_on_insert','ingest.metarecord_mapping.skip_on_update','ingest.reingest.force_on_same_marc','ingest.skip_browse_indexing','ingest.skip_facet_indexing','ingest.skip_search_indexing');

UPDATE biblio.record_entry SET marc = marc;

UPDATE config.internal_flag SET enabled = FALSE WHERE name IN (
'ingest.assume_inserts_only','ingest.disable_authority_auto_update','ingest.disable_authority_linking','ingest.disable_located_uri','ingest.disable_metabib_field_entry','ingest.disable_metabib_full_rec','ingest.disable_metabib_rec_descriptor','ingest.metarecord_mapping.preserve_on_delete','ingest.metarecord_mapping.skip_on_insert','ingest.metarecord_mapping.skip_on_update','ingest.reingest.force_on_same_marc','ingest.skip_browse_indexing','ingest.skip_facet_indexing','ingest.skip_search_indexing');
COMMIT;

