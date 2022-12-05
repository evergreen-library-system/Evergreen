COPY acq.fund (id, org, name, year, currency_type, code, rollover, propagate, active, balance_warning_percent, balance_stop_percent) FROM stdin;
1	1	Adult	2020	USD	AD	0	1	1	\N	\N
2	2	AV	2020	USD	AV	0	1	1	\N	\N
3	3	AV	2020	USD	AV	0	1	1	\N	\N
4	4	Juvenile	2020	USD	JUV	0	1	1	\N	\N
5	5	Young Adult	2020	USD	YA	0	1	1	\N	\N
6	6	Juvenile	2020	USD	JUV	0	1	1	\N	\N
7	7	Young Adult	2020	USD	YA	0	1	1	\N	\N
8	2	Reference	2020	USD	RF	0	1	1	\N	\N
9	2	Fiction Print	2020	USD	FP	0	1	1	\N	\N
10	2	Fiction Non-Print	2020	USD	FNP	0	1	1	\N	\N
11	3	Fiction Print	2020	USD	FP	0	1	1	\N	\N
12	3	Fiction Non-Print	2020	USD	FNP	0	1	1	\N	\N
13	107	Young Adult	2022	USD	YA	0	1	1	\N	100
14	107	Adult	2022	USD	ADULT	0	1	1	\N	\N
\.

\echo sequence update column: id
SELECT SETVAL('acq.fund_id_seq', (SELECT MAX(id) FROM acq.fund));
