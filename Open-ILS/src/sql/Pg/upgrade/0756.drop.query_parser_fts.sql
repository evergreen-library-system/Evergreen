BEGIN;

SELECT evergreen.upgrade_deps_block_check('0756', :eg_version);

-- Drop some lingering old functions in search schema
DROP FUNCTION IF EXISTS search.staged_fts(INT,INT,TEXT,INT[],INT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT,TEXT,TEXT,TEXT[],TEXT,REAL,TEXT,BOOL,BOOL,BOOL,INT,INT,INT);
DROP FUNCTION IF EXISTS search.parse_search_args(TEXT);
DROP FUNCTION IF EXISTS search.explode_array(ANYARRAY);
DROP FUNCTION IF EXISTS search.pick_table(TEXT);

-- Now drop query_parser_fts and related
DROP FUNCTION IF EXISTS search.query_parser_fts(INT,INT,TEXT,INT[],INT[],INT,INT,INT,BOOL,BOOL,INT);
DROP TYPE IF EXISTS search.search_result;
DROP TYPE IF EXISTS search.search_args;

COMMIT;
