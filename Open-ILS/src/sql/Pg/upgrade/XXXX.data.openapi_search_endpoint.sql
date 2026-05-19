BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

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

COMMIT;
