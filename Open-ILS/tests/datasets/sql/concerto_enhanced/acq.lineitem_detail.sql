COPY acq.lineitem_detail (id, lineitem, fund, fund_debit, eg_copy_id, barcode, cn_label, note, collection_code, circ_modifier, owning_lib, location, recv_time, receiver, cancel_reason) FROM stdin;
1	3	1	1	3	ACQ0001	ACQ001	\N	\N	\N	4	113	\N	\N	\N
2	3	1	2	103	ACQ0002	ACQ002	\N	\N	\N	5	125	\N	\N	\N
3	4	1	3	4	ACQ0002	ACQ002	\N	\N	\N	4	118	\N	\N	1
4	5	1	\N	5	ACQ0002	ACQ002	\N	\N	\N	4	123	\N	\N	1283
5	59	13	164	4806	ACQ5	ACQ5	\N	\N	\N	103	158	\N	\N	\N
6	60	13	175	4817	ACQ6	ACQ6	\N	\N	\N	103	158	2022-06-17 10:47:52.495696-05	1	\N
7	61	13	166	4808	ACQ7	ACQ7	\N	\N	\N	103	158	2022-06-17 10:47:52.495696-05	1	\N
8	62	13	\N	4818	ACQ8	ACQ8	\N	\N	\N	103	158	\N	\N	1285
9	63	13	205	4847	ACQ9	ACQ9	\N	\N	\N	103	158	\N	\N	\N
10	64	13	177	4819	ACQ10	ACQ10	\N	\N	\N	103	158	\N	\N	\N
11	65	13	178	4820	ACQ11	ACQ11	\N	\N	\N	103	158	\N	\N	1283
12	66	13	206	4848	ACQ12	ACQ12	\N	\N	\N	103	158	\N	\N	\N
13	67	14	179	4821	ACQ13	ACQ13	\N	\N	\N	103	158	\N	\N	1283
14	68	13	207	4849	ACQ14	ACQ14	\N	\N	\N	103	158	\N	\N	\N
15	69	14	167	4809	ACQ15	ACQ15	\N	\N	\N	103	158	2022-06-17 10:47:52.495696-05	1	\N
16	70	13	180	4822	ACQ16	ACQ16	\N	\N	\N	103	158	\N	\N	\N
17	71	13	209	4851	ACQ17	ACQ17	\N	\N	\N	103	158	2022-06-17 10:47:52.495696-05	1	\N
18	72	13	168	4810	ACQ18	ACQ18	\N	\N	\N	103	158	\N	\N	\N
19	73	14	210	4852	ACQ19	ACQ19	\N	\N	\N	103	158	\N	\N	1283
20	74	14	165	4807	ACQ20	ACQ20	\N	\N	\N	103	158	\N	\N	\N
21	75	14	169	4811	ACQ21	ACQ21	\N	\N	\N	103	158	\N	\N	1283
22	76	13	181	4823	ACQ22	ACQ22	\N	\N	\N	103	158	\N	\N	\N
23	77	13	174	4816	ACQ23	ACQ23	\N	\N	\N	103	158	\N	\N	1283
24	78	13	189	4831	ACQ24	ACQ24	\N	\N	\N	103	158	2022-06-17 10:47:52.495696-05	1	\N
25	79	13	182	4824	ACQ25	ACQ25	\N	\N	\N	103	158	2022-06-17 10:47:52.495696-05	1	\N
26	80	14	170	4812	ACQ26	ACQ26	\N	\N	\N	103	158	\N	\N	\N
27	81	14	198	4840	ACQ27	ACQ27	\N	\N	\N	103	158	\N	\N	\N
28	82	13	183	4825	ACQ28	ACQ28	\N	\N	\N	103	158	\N	\N	\N
29	83	13	172	4814	ACQ29	ACQ29	\N	\N	\N	103	158	\N	\N	\N
30	84	14	184	4826	ACQ30	ACQ30	\N	\N	\N	103	158	\N	\N	\N
31	85	13	185	4827	ACQ31	ACQ31	\N	\N	\N	103	158	\N	\N	\N
32	86	14	208	4850	ACQ32	ACQ32	\N	\N	\N	103	158	\N	\N	\N
33	87	13	186	4828	ACQ33	ACQ33	\N	\N	\N	103	158	\N	\N	\N
34	88	13	\N	4813	ACQ34	ACQ34	\N	\N	\N	103	158	\N	\N	1285
35	89	13	187	4829	ACQ35	ACQ35	\N	\N	\N	103	158	\N	\N	\N
36	90	14	188	4830	ACQ36	ACQ36	\N	\N	\N	103	158	\N	\N	\N
37	91	13	173	4815	ACQ37	ACQ37	\N	\N	\N	103	158	\N	\N	\N
38	92	13	211	4853	ACQ38	ACQ38	\N	\N	\N	103	158	\N	\N	\N
39	93	13	\N	4832	ACQ39	ACQ39	\N	\N	\N	103	158	\N	\N	1285
40	94	14	191	4833	ACQ40	ACQ40	\N	\N	\N	103	158	\N	\N	\N
41	95	13	212	4854	ACQ41	ACQ41	\N	\N	\N	103	158	\N	\N	\N
42	96	13	192	4834	ACQ42	ACQ42	\N	\N	\N	103	158	\N	\N	\N
43	97	14	193	4835	ACQ43	ACQ43	\N	\N	\N	103	158	\N	\N	\N
44	98	13	194	4836	ACQ44	ACQ44	\N	\N	\N	103	158	\N	\N	\N
45	99	13	195	4837	ACQ45	ACQ45	\N	\N	\N	103	158	\N	\N	\N
46	100	14	213	4855	ACQ46	ACQ46	\N	\N	\N	103	158	\N	\N	\N
47	101	13	196	4838	ACQ47	ACQ47	\N	\N	\N	103	158	\N	\N	\N
48	102	13	197	4839	ACQ48	ACQ48	\N	\N	\N	103	158	\N	\N	\N
49	103	13	214	4856	ACQ49	ACQ49	\N	\N	\N	103	158	\N	\N	\N
50	104	13	215	4857	ACQ50	ACQ50	\N	\N	\N	103	158	\N	\N	\N
51	105	13	201	4843	ACQ51	ACQ51	\N	\N	\N	103	158	\N	\N	\N
52	106	13	199	4841	ACQ52	ACQ52	\N	\N	\N	103	158	\N	\N	\N
53	107	13	200	4842	ACQ53	ACQ53	\N	\N	\N	103	158	\N	\N	\N
54	108	13	216	4858	ACQ54	ACQ54	\N	\N	\N	103	158	\N	\N	\N
55	109	13	202	4844	ACQ55	ACQ55	\N	\N	\N	103	158	\N	\N	\N
56	110	13	204	4846	ACQ56	ACQ56	\N	\N	\N	103	158	\N	\N	\N
57	111	13	203	4845	ACQ57	ACQ57	\N	\N	\N	103	158	\N	\N	\N
\.

\echo sequence update column: id
SELECT SETVAL('acq.lineitem_detail_id_seq', (SELECT MAX(id) FROM acq.lineitem_detail));