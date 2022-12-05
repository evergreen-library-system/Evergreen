COPY serial.basic_summary (id, distribution, generated_coverage, textual_holdings, show_generated) FROM stdin;
1	1	["v.97:no.1(2022:Jan.03)"]	\N	1
2	10	["2022:Jan.01"]	\N	1
3	12	["2022:Jan.17"]	\N	1
4	19	["v.23:no.1(2022:Jan./Feb.)"]	\N	1
5	18	["v.23:no.1(2022:Jan./Feb.)"]	\N	1
6	23	["v.241:no.1(2022:Jan.)"]	\N	1
\.

\echo sequence update column: id
SELECT SETVAL('serial.basic_summary_id_seq', (SELECT MAX(id) FROM serial.basic_summary));
