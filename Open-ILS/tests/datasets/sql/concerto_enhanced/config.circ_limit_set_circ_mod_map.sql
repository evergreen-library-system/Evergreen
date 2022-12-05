COPY config.circ_limit_set_circ_mod_map (id, limit_set, circ_mod) FROM stdin;
1	1	videogame
2	1	videogame new
3	1	software
\.

\echo sequence update column: id
SELECT SETVAL('config.circ_limit_set_circ_mod_map_id_seq', (SELECT MAX(id) FROM config.circ_limit_set_circ_mod_map));
