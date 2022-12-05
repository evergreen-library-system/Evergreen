COPY booking.resource_attr_map (id, resource, resource_attr, value) FROM stdin;
1	33	1	1
3	33	2	5
4	34	2	4
5	35	2	4
6	36	1	2
7	41	3	6
8	37	3	6
9	39	3	7
10	40	3	6
11	42	4	8
12	43	4	9
13	44	4	10
14	49	4	11
15	45	5	12
16	46	5	13
17	54	7	14
19	55	7	15
20	56	7	16
21	57	7	17
22	58	7	18
23	59	7	19
24	50	9	20
25	51	9	21
26	52	9	22
27	53	9	8
28	60	8	24
29	61	8	25
30	62	8	26
\.

\echo sequence update column: id
SELECT SETVAL('booking.resource_attr_map_id_seq', (SELECT MAX(id) FROM booking.resource_attr_map));
