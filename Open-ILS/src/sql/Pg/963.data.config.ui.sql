
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
