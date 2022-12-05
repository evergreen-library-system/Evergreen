COPY config.floating_group (id, name, manual) FROM stdin;
2	System	0
\.

\echo sequence update column: id
SELECT SETVAL('config.floating_group_id_seq', (SELECT MAX(id) FROM config.floating_group));
