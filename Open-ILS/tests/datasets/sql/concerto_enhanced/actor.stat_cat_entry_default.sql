COPY actor.stat_cat_entry_default (id, stat_cat_entry, stat_cat, owner) FROM stdin;
1	30	3	1
2	32	4	101
\.

\echo sequence update column: id
SELECT SETVAL('actor.stat_cat_entry_default_id_seq', (SELECT MAX(id) FROM actor.stat_cat_entry_default));
