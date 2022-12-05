COPY actor.stat_cat_entry_usr_map (id, stat_cat_entry, stat_cat, target_usr) FROM stdin;
1	Yes	3	244
2	Other / Not Listed	2	245
3	Yes	3	245
4	Yes	3	260
9	Czech	2	280
10	No	3	280
\.

\echo sequence update column: id
SELECT SETVAL('actor.stat_cat_entry_usr_map_id_seq', (SELECT MAX(id) FROM actor.stat_cat_entry_usr_map));
