
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1074', :eg_version);

INSERT INTO config.internal_flag (name, enabled) 
    VALUES ('ingest.skip_display_indexing', FALSE);

-- Adds seed data to replace (for now) values from the 'mvr' class

UPDATE config.metabib_field SET display_field = TRUE WHERE id IN (6, 8, 16, 18);

INSERT INTO config.metabib_field ( id, field_class, name, label,
    format, xpath, display_field, display_xpath ) VALUES
    (37, 'author', 'creator', oils_i18n_gettext(37, 'All Creators', 'cmf', 'label'),
     'mods32', $$//mods32:mods/mods32:name[mods32:role/mods32:roleTerm[text()='creator']]$$, 
     TRUE, $$//*[local-name()='namePart']$$ ); -- /* to fool vim */;

-- 'author' field
UPDATE config.metabib_field SET display_xpath = 
    $$//*[local-name()='namePart']$$ -- /* to fool vim */
    WHERE id = 8;

INSERT INTO config.display_field_map (name, field, multi) VALUES
    ('title', 6, FALSE),
    ('author', 8, FALSE),
    ('creators', 37, TRUE),
    ('subject', 16, TRUE),
    ('isbn', 18, TRUE)
;

COMMIT;

-- REINGEST DISPLAY ENTRIES
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE, TRUE, 
    (SELECT ARRAY_AGG(id)::INT[] FROM config.metabib_field WHERE display_field))
    FROM biblio.record_entry WHERE NOT deleted AND id > 0;

