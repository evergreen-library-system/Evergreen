COPY acq.provider_holding_subfield_map (id, provider, name, subfield) FROM stdin;
1	1	quantity	q
2	1	estimated_price	p
3	1	owning_lib	o
4	1	call_number	n
5	1	fund_code	f
6	1	circ_modifier	m
7	1	note	z
8	1	copy_location	l
9	1	barcode	b
10	1	collection_code	c
11	2	quantity	q
12	2	estimated_price	p
13	2	owning_lib	o
14	2	call_number	n
15	2	fund_code	f
16	2	circ_modifier	m
17	2	note	z
18	2	copy_location	l
19	2	barcode	b
20	2	collection_code	c
21	3	quantity	q
22	3	estimated_price	p
23	3	owning_lib	o
24	3	call_number	n
25	3	fund_code	f
26	3	circ_modifier	m
27	3	note	z
28	3	copy_location	l
29	3	barcode	b
30	3	collection_code	c
31	4	quantity	q
32	4	estimated_price	p
33	4	owning_lib	o
34	4	call_number	n
35	4	fund_code	f
36	4	circ_modifier	m
37	4	note	z
38	4	copy_location	l
39	4	barcode	b
40	4	collection_code	c
\.

\echo sequence update column: id
SELECT SETVAL('acq.provider_holding_subfield_map_id_seq', (SELECT MAX(id) FROM acq.provider_holding_subfield_map));
