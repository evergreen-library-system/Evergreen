COPY config.circ_limit_set_copy_loc_map (id, limit_set, copy_loc) FROM stdin;
1	3	164
\.

\echo sequence update column: id
SELECT SETVAL('config.circ_limit_set_copy_loc_map_id_seq', (SELECT MAX(id) FROM config.circ_limit_set_copy_loc_map));
