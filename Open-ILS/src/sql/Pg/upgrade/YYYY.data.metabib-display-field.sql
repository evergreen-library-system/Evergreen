
BEGIN;

INSERT INTO config.internal_flag (name, enabled) 
    VALUES ('ingest.skip_display_indexing', FALSE);

-- Adds seed data to replace (for now) values from the 'mvr' class

UPDATE config.metabib_field SET display_field = TRUE WHERE id IN (6, 8, 14, 16, 18);

INSERT INTO config.display_field_map (name, field, multi) VALUES
    ('title', 6, FALSE),
    ('author', 8, FALSE),
    ('subject', 16, TRUE),
    ('topic_subject', 14, TRUE),
    ('isbn', 18, TRUE)
;

UPDATE config.metabib_class SET representative_field = 6 WHERE name = 'title';
UPDATE config.metabib_class SET representative_field = 8 WHERE name = 'author';

COMMIT;

-- REINGEST DISPLAY ENTRIES
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE, TRUE, '{6,8,14,16,18}'::INT[]) FROM biblio.record_entry WHERE NOT deleted AND id > 0;

