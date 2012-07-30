BEGIN;

SELECT evergreen.upgrade_deps_block_check('0728', :eg_version);

INSERT INTO actor.search_filter_group (owner, code, label) 
    VALUES (1, 'kpac_main', 'Kid''s OPAC Search Filter');

INSERT INTO actor.search_query (label, query_text) 
    VALUES ('Children''s Materials', 'audience(a,b,c)');
INSERT INTO actor.search_query (label, query_text) 
    VALUES ('Young Adult Materials', 'audience(j,d)');
INSERT INTO actor.search_query (label, query_text) 
    VALUES ('General/Adult Materials',  'audience(e,f,g, )');

INSERT INTO actor.search_filter_group_entry (grp, query, pos)
    VALUES (
        (SELECT id FROM actor.search_filter_group WHERE code = 'kpac_main'),
        (SELECT id FROM actor.search_query WHERE label = 'Children''s Materials'),
        0
    );
INSERT INTO actor.search_filter_group_entry (grp, query, pos) 
    VALUES (
        (SELECT id FROM actor.search_filter_group WHERE code = 'kpac_main'),
        (SELECT id FROM actor.search_query WHERE label = 'Young Adult Materials'),
        1
    );
INSERT INTO actor.search_filter_group_entry (grp, query, pos) 
    VALUES (
        (SELECT id FROM actor.search_filter_group WHERE code = 'kpac_main'),
        (SELECT id FROM actor.search_query WHERE label = 'General/Adult Materials'),
        2
    );

COMMIT;

