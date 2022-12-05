COPY container.carousel_org_unit (id, carousel, override_name, org_unit, seq) FROM stdin;
1	1	\N	1	2
2	2	\N	101	0
3	3	\N	4	0
4	4	\N	6	0
6	5	Staff Suggestions	1	1
8	6	\N	7	1
\.

\echo sequence update column: id
SELECT SETVAL('container.carousel_org_unit_id_seq', (SELECT MAX(id) FROM container.carousel_org_unit));
