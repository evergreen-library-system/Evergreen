COPY acq.funding_source_credit (id, funding_source, amount, note, deadline_date, effective_date) FROM stdin;
1	1	10000	\N	\N	2020-10-27 10:26:51.426709-04
2	2	5000	\N	\N	2020-10-27 10:26:51.426709-04
3	3	5000	\N	\N	2020-10-27 10:26:51.426709-04
\.

\echo sequence update column: id
SELECT SETVAL('acq.funding_source_credit_id_seq', (SELECT MAX(id) FROM acq.funding_source_credit));
