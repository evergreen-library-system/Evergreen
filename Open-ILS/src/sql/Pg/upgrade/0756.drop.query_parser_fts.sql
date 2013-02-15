BEGIN;

SELECT evergreen.upgrade_deps_block_check('0756', :eg_version);

DROP FUNCTION IF EXISTS search.query_parser_fts(INT,INT,TEXT,INT[],INT[],INT,INT,INT,BOOL,BOOL,INT);
DROP TYPE IF EXISTS search.search_result;
DROP TYPE IF EXISTS search.search_args;

COMMIT;
