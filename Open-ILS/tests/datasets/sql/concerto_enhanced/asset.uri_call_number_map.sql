COPY asset.uri_call_number_map (id, uri, call_number) FROM stdin;
1	1	1
2	1	2
3	1	3
4	1	4
7	1	7
8	1	8
9	1	9
10	1	10
11	1	11
12	1	12
13	1	13
14	1	14
15	1	15
16	1	16
17	1	17
18	1	18
19	1	19
20	1	20
21	1	21
22	1	22
23	1	23
24	1	24
25	1	25
26	1	26
27	1	27
28	1	28
29	1	29
30	1	30
31	1	31
32	1	32
33	1	33
34	1	34
35	1	35
40	11	1757
41	10	1758
42	9	1759
43	8	1760
44	1	1761
45	1	1762
\.

\echo sequence update column: id
SELECT SETVAL('asset.uri_call_number_map_id_seq', (SELECT MAX(id) FROM asset.uri_call_number_map));
