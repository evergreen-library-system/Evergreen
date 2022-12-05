COPY asset.copy_part_map (id, target_copy, part) FROM stdin;
1	353	7
2	385	3
3	853	7
4	885	2
5	1353	7
6	1385	4
7	1853	5
8	1885	2
9	2353	7
10	2385	1
11	3101	5
12	3102	2
13	3103	8
14	3104	4
\.

\echo sequence update column: id
SELECT SETVAL('asset.copy_part_map_id_seq', (SELECT MAX(id) FROM asset.copy_part_map));
