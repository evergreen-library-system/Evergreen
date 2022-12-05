COPY acq.fund_allocation (id, funding_source, fund, amount, allocator, note, create_time) FROM stdin;
1	1	1	3000	1	\N	2020-10-27 09:26:51.426709-05
2	1	2	3000	1	\N	2020-10-27 09:26:51.426709-05
3	1	3	3000	1	\N	2020-10-27 09:26:51.426709-05
4	2	9	500	1	\N	2020-10-27 09:26:51.426709-05
5	2	10	500	1	\N	2020-10-27 09:26:51.426709-05
6	3	4	2000	1	\N	2020-10-27 09:26:51.426709-05
7	2	14	2000	1	\N	2022-06-17 10:41:15.660314-05
8	2	13	2000	1	\N	2022-06-17 10:41:32.358234-05
9	2	13	-125.00	1	Transfer to fund ADULT (2022) (WAKA)	2022-06-17 10:54:49.956568-05
10	2	14	125.00	1	Transfer from fund YA (2022) (WAKA)	2022-06-17 10:54:49.956568-05
\.

\echo sequence update column: id
SELECT SETVAL('acq.fund_allocation_id_seq', (SELECT MAX(id) FROM acq.fund_allocation));
