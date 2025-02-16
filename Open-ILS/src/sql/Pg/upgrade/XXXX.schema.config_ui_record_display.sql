BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

DO $$ BEGIN
CREATE TYPE config.ui_record_display_entry_type AS ENUM ('search_result', 'staff_view');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
CREATE TYPE config.ui_record_display_entry_content_type AS ENUM (
    'field', 'formats_and_editions', 'hold_counts', 'item_counts'
);
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS config.ui_record_display_entry (
    id              SERIAL PRIMARY KEY,
    type            config.ui_record_display_entry_type,
    content_type    config.ui_record_display_entry_content_type,
    page_col        INTEGER NOT NULL,
    col_pos         INTEGER NOT NULL,
    field           INT, -- REFERENCES config.metabib_field (id)
    value_limit     INTEGER,
    character_limit INTEGER,
    display_as_link BOOLEAN
    CONSTRAINT must_specify_whether_field_entry_should_be_a_link CHECK (content_type != 'field'::config.ui_record_display_entry_content_type OR display_as_link IS NOT NULL),
    CONSTRAINT incompatible_options CHECK (content_type = 'field'::config.ui_record_display_entry_content_type OR (display_as_link IS NULL AND value_limit IS NULL AND character_limit is NULL))
);

ALTER TABLE config.ui_record_display_entry ADD CONSTRAINT curde_field_fkey
    FOREIGN KEY (field) REFERENCES config.metabib_field(id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


INSERT INTO config.ui_record_display_entry
    (type, content_type, page_col, col_pos, field, display_as_link)
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 1, id, TRUE FROM config.metabib_field WHERE field_class = 'title' AND name = 'proper' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 2, id, TRUE FROM config.metabib_field WHERE field_class = 'series' AND name = 'seriestitle' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 3, id, TRUE FROM config.metabib_field WHERE field_class = 'author' AND name = 'first_author' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 4, id, TRUE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'performers' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 5, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'edition' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 6, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'origin_info' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 7, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'production_credits' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 8, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'type_of_resource' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 9, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'physical_description' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 10, id, TRUE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'isbn' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 11, id, TRUE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'issn' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 12, id, TRUE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'upc' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 2, 1, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'abstract' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 2, 2, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'general_note' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 2, 3, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'bibliography' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 2, 4, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'toc' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 2, 5, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'thesis' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'item_counts'::config.ui_record_display_entry_content_type, 3, 1, NULL, NULL UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'hold_counts'::config.ui_record_display_entry_content_type, 3, 2, NULL, NULL UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 3, 3, id, TRUE FROM config.metabib_field WHERE field_class = 'subject' AND name = 'complete' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 3, 4, id, TRUE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'genre' UNION
    SELECT 'staff_view'::config.ui_record_display_entry_type, 'formats_and_editions'::config.ui_record_display_entry_content_type, 3, 5, NULL, NULL;

INSERT INTO config.ui_record_display_entry
    (type, content_type, page_col, col_pos, field, display_as_link)
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 1, id, FALSE FROM config.metabib_field WHERE field_class = 'series' AND name = 'seriestitle' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 2, id, FALSE FROM config.metabib_field WHERE field_class = 'keyword' AND name = 'physical_description' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 3, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'edition' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 4, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'origin_info' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 5, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'pubdate' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 6, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'isbn' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 7, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'upc' UNION
    SELECT 'search_result'::config.ui_record_display_entry_type, 'field'::config.ui_record_display_entry_content_type, 1, 8, id, FALSE FROM config.metabib_field WHERE field_class = 'identifier' AND name = 'issn';

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
    696,
    'ADMIN_RECORD_DISPLAY',
    oils_i18n_gettext(696,
        'Allow modifying the display of catalog records in certain interfaces', 'ppl', 'description'
    )
    FROM permission.perm_list
    WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_RECORD_DISPLAY');

COMMIT;
