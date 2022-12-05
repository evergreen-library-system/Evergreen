COPY serial.distribution (id, record_entry, summary_method, subscription, holding_lib, label, display_grouping, receive_call_number, receive_unit_template, bind_call_number, bind_unit_template, unit_label_prefix, unit_label_suffix) FROM stdin;
1	\N	\N	1	4	BR1	chron	\N	1	\N	\N	\N	\N
2	\N	\N	2	4	BR1	chron	\N	1	\N	\N	\N	\N
3	\N	\N	3	4	BR1	chron	\N	1	\N	\N	\N	\N
4	\N	\N	4	4	BR1	chron	\N	1	\N	\N	\N	\N
5	\N	\N	5	4	BR1	chron	\N	1	\N	\N	\N	\N
6	\N	\N	6	4	BR1	chron	\N	1	\N	\N	\N	\N
7	\N	\N	7	4	BR1	chron	\N	1	\N	\N	\N	\N
8	\N	\N	8	4	BR1	chron	\N	1	\N	\N	\N	\N
9	\N	\N	9	4	BR1	chron	\N	1	\N	\N	\N	\N
10	\N	\N	10	4	BR1	chron	\N	2	\N	\N	\N	\N
11	\N	\N	11	5	BR2	chron	\N	3	\N	\N	\N	\N
12	\N	\N	12	5	BR2	chron	\N	3	\N	\N	\N	\N
13	\N	\N	13	5	BR2	chron	\N	3	\N	\N	\N	\N
14	\N	\N	14	5	BR2	chron	\N	3	\N	\N	\N	\N
15	\N	\N	15	5	BR2	chron	\N	3	\N	\N	\N	\N
16	\N	\N	16	5	BR2	chron	\N	3	\N	\N	\N	\N
17	\N	\N	17	5	BR2	chron	\N	3	\N	\N	\N	\N
18	\N	\N	18	5	BR2-Circ	chron	\N	3	\N	\N	\N	\N
19	\N	\N	18	5	BR2-Genealogy	chron	\N	4	\N	\N	\N	\N
20	\N	\N	19	5	BR2	chron	\N	3	\N	\N	\N	\N
21	\N	\N	20	5	BR2	chron	\N	3	\N	\N	\N	\N
22	\N	\N	21	6	BR3	chron	\N	6	\N	\N	\N	\N
23	\N	\N	22	6	BR3	chron	\N	5	\N	\N	\N	\N
24	\N	\N	23	6	BR3	chron	\N	5	\N	\N	\N	\N
25	\N	\N	24	6	BR3	chron	\N	5	\N	\N	\N	\N
26	\N	\N	25	6	BR3	chron	\N	5	\N	\N	\N	\N
27	\N	\N	26	6	BR3	chron	\N	5	\N	\N	\N	\N
28	\N	\N	27	6	BR3	chron	\N	5	\N	\N	\N	\N
\.

\echo sequence update column: id
SELECT SETVAL('serial.distribution_id_seq', (SELECT MAX(id) FROM serial.distribution));
