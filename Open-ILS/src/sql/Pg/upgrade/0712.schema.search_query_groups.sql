
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0712', :eg_version);

-- General purpose query container.  Any table the needs to store
-- a QueryParser query should store it here.  This will be the 
-- source for top-level and QP sub-search inclusion queries.
CREATE TABLE actor.search_query (
    id          SERIAL PRIMARY KEY, 
    label       TEXT NOT NULL, -- i18n
    query_text  TEXT NOT NULL -- QP text
);

-- e.g. "Reading Level"
CREATE TABLE actor.search_filter_group (
    id          SERIAL      PRIMARY KEY,
    owner       INT         NOT NULL REFERENCES actor.org_unit (id) 
                            ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    code        TEXT        NOT NULL, -- for CGI, etc.
    label       TEXT        NOT NULL, -- i18n
    create_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT  asfg_label_once_per_org UNIQUE (owner, label),
    CONSTRAINT  asfg_code_once_per_org UNIQUE (owner, code)
);

-- e.g. "Adult", "Teen", etc.
CREATE TABLE actor.search_filter_group_entry (
    id          SERIAL  PRIMARY KEY,
    grp         INT     NOT NULL REFERENCES actor.search_filter_group(id) 
                        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    pos         INT     NOT NULL DEFAULT 0,
    query       INT     NOT NULL REFERENCES actor.search_query(id) 
                        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT asfge_query_once_per_group UNIQUE (grp, query)
);

COMMIT;

/*
-- Fictional Example
BEGIN;

INSERT INTO actor.search_filter_group (owner, code, label) 
    VALUES (4, 'reading_level', 'Reading Level');

INSERT INTO actor.search_query (label, query_text) 
    VALUES ('Children', 'audience(a,b,c) locations(3,4,5,6)');
INSERT INTO actor.search_query (label, query_text) 
    VALUES ('Juvenile', 'audience(j,d) locations(1,2,7,8)');
INSERT INTO actor.search_query (label, query_text) 
    VALUES ('General',  'audience(e,f,g)');

INSERT INTO actor.search_filter_group_entry (grp, query)
    VALUES (
        (SELECT id FROM actor.search_filter_group WHERE code = 'reading_level'),
        (SELECT id FROM actor.search_query WHERE label = 'Children')
    );
INSERT INTO actor.search_filter_group_entry (grp, query) 
    VALUES (
        (SELECT id FROM actor.search_filter_group WHERE code = 'reading_level'),
        (SELECT id FROM actor.search_query WHERE label = 'Juvenile')
    );
INSERT INTO actor.search_filter_group_entry (grp, query) 
    VALUES (
        (SELECT id FROM actor.search_filter_group WHERE code = 'reading_level'),
        (SELECT id FROM actor.search_query WHERE label = 'General')
    );

COMMIT;
*/

/* 
-- UNDO
BEGIN;
DROP TABLE actor.search_filter_group_entry;
DROP TABLE actor.search_filter_group;
DROP TABLE actor.search_query;
COMMIT;
*/
