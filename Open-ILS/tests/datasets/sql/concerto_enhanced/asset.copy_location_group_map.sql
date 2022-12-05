COPY asset.copy_location_group_map (id, location, lgroup) FROM stdin;
1	103	1
2	104	1
3	110	1
4	112	1
5	113	1
6	114	1
7	116	1
8	129	2
9	130	2
10	143	2
11	144	2
\.

\echo sequence update column: id
SELECT SETVAL('asset.copy_location_group_map_id_seq', (SELECT MAX(id) FROM asset.copy_location_group_map));
