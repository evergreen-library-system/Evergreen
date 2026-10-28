--Upgrade Script for 3.17.6 to 3.18-rc
\set eg_version '''3.18-rc'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.18-rc', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1524', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   695,
   'ADMIN_CALL_NUMBER_CLASS',
   oils_i18n_gettext(695,
     'Allow updates to call number classification names, normalizers, and fields.', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CALL_NUMBER_CLASS');

CREATE OR REPLACE FUNCTION evergreen.function_exists(function_name TEXT) RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM information_schema.routines WHERE CONCAT(routine_schema, '.', routine_name) = function_name);
$$
LANGUAGE SQL
VOLATILE;

ALTER TABLE asset.call_number_class ADD CONSTRAINT asset_call_number_class_has_valid_normalizer
    CHECK (evergreen.function_exists(normalizer));


SELECT evergreen.upgrade_deps_block_check('1529', :eg_version);

INSERT INTO openapi.endpoint_set
(name, description, active, rate_limit)
VALUES
('coded_value_maps', 'Methods for retrieving coded value maps', TRUE, NULL),
('search', 'Methods for searching the catalog of bibliographic records', 't', NULL)
ON CONFLICT DO NOTHING;

-- coded_value_maps and search do not need extra permissions.

INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name,
 method_params)
VALUES (
  'retrieveCodedValueMap',
  '/coded_value_map/:id',
  'get',
  'Retrieve one coded value map by id',
  'OpenILS::OpenAPI::Controller::ccvm',
  'retrieve_ccvm',
  'param.id'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, in_part, schema_type, required)
VALUES
('retrieveCodedValueMap', 'id', 'path', 'integer', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response (endpoint, fm_type)
VALUES ('retrieveCodedValueMap', 'ccvm') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name,
 method_params)
VALUES (
  'codedValueMapsByCtype',
  '/coded_value_maps/by_ctype/:ctype',
  'get',
  'Retrieve coded value maps by ctype',
  'OpenILS::OpenAPI::Controller::ccvm',
  'ccvm_by_ctype',
  'param.ctype'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, in_part, schema_type, required)
VALUES
('codedValueMapsByCtype', 'ctype', 'path', 'string', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items)
VALUES ('codedValueMapsByCtype','array','object') ON CONFLICT DO NOTHING;

-- New search endpoint(s)
INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name, method_params)
VALUES (
    'searchMulticlass',
    '/search/multiclass',
    'get',
    'Search bibliographic records similar to the OPAC',
    'OpenILS::OpenAPI::Controller::search',
    'multiclass_search',
    'eg_auth_token every_param.title every_param.author every_param.subject every_param.series every_param.keyword every_param.identifier every_param.isbn every_param.issn param.org_unit param.depth param.limit param.offset param.sort param.sort_dir param.tag_circulated_records param.query param.docache'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, required, in_part, schema_type, default_value)
VALUES
('searchMulticlass', 'title', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'author', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'subject', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'series', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'keyword', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'identifier', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'isbn', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'issn', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'query', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'sort', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'sort_dir', FALSE, 'query', 'string', 'ASC')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, required, in_part, schema_type, default_value)
VALUES
('searchMulticlass', 'org_unit', FALSE, 'query', 'integer', NULL),
('searchMulticlass', 'depth', FALSE, 'query', 'integer', NULL),
('searchMulticlass', 'limit', FALSE, 'query', 'integer', '10'),
('searchMulticlass', 'offset', FALSE, 'query', 'integer', '0')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, required, in_part, schema_type, default_value)
VALUES
('searchMulticlass', 'tag_circulated_records', FALSE, 'query', 'boolean', 'false'),
('searchMulticlass', 'docache', FALSE, 'query', 'boolean', 'true')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response (endpoint, schema_type)
VALUES ('searchMulticlass', 'object') ON CONFLICT DO NOTHING;

-- New bibs endpoint to retrieve record by identifier

INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name, method_params)
VALUES (
  'bibByISBN',
  '/bibs/by_isbn/:isbn',
  'get',
  'Retrieve bib record by ISBN or other standard identifier',
  'OpenILS::OpenAPI::Controller::bib',
  'retrieve_bib',
  'param.isbn'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, in_part, schema_type, required)
VALUES
('bibByISBN', 'isbn', 'path', 'string', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response
(endpoint, content_type, fm_type)
VALUES
('bibByISBN', 'application/json', 'bre')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response
(endpoint, content_type)
VALUES
('bibByISBN', 'application/xml'),
('bibByISBN', 'application/octet-stream')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_set_endpoint_map (endpoint, endpoint_set)
  SELECT e.operation_id, s.name FROM openapi.endpoint e JOIN openapi.endpoint_set s ON (e.path LIKE '/'||RTRIM(s.name,'s')||'%')
ON CONFLICT DO NOTHING;


SELECT evergreen.upgrade_deps_block_check('1530', :eg_version);

--remove entry from settings table
DELETE FROM actor.org_unit_setting
WHERE name='circ.hold_stalling_hard';

--remove entries from log table
DELETE FROM config.org_unit_setting_type_log
WHERE field_name='circ.hold_stalling_hard';

--Remove unused org unit setting
DELETE FROM config.org_unit_setting_type
WHERE name='circ.hold_stalling_hard';


SELECT evergreen.upgrade_deps_block_check('1532', :eg_version);

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


SELECT evergreen.upgrade_deps_block_check('1533', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.bucket.batch_hold.event_holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.cat.bucket.batch_hold.event_holds',
        'Grid Config: eg.grid.cat.bucket.batch_hold.event_holds',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1534', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES
(697, 'PURGE_USER', oils_i18n_gettext(697,
    'Allow a user to delete (purge) another user', 'ppl', 'description'));

-- Grant the PURGE_USER permission to any group that has DELETE_USER.
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('PURGE_USER'))
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map

        /* Don't add the permission if it's already assigned. I'm
        not sure if that's possible, but it seems we usually check
        for this in upgrade scripts like this, so here we go. */
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)

        -- Add the permission to any group that has DELETE_USER
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'DELETE_USER'
        );


SELECT evergreen.upgrade_deps_block_check('1536', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES (
    698, 'DELETE_INACTIVE_NONPRIMARY_PATRON_CARD',
    oils_i18n_gettext(
        698,
        'Allow a user to delete a patron''s inactive, non-primary cards',
        'ppl',
        'description'
    )
);

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
