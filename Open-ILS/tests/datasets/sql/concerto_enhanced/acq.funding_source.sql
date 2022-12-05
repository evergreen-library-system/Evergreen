COPY acq.funding_source (id, name, owner, currency_type, code, active) FROM stdin;
1	LSTA	1	USD	LSTA	1
2	State	2	USD	ST	1
3	Foundation	4	USD	FNTN	1
\.

\echo sequence update column: id
SELECT SETVAL('acq.funding_source_id_seq', (SELECT MAX(id) FROM acq.funding_source));
