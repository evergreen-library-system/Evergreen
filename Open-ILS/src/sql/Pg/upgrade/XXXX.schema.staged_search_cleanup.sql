BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

DROP FUNCTION search.query_parser_fts (
    INT,
    INT,
    TEXT,
    INT[],
    INT[],
    INT,
    INT,
    INT,
    BOOL,
    BOOL,
    BOOL,
    INT 
);

DROP TABLE asset.opac_visible_copies;

COMMIT;
