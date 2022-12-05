COPY config.rule_max_fine (id, name, amount, is_percent) FROM stdin;
101	no_fines	0.00	0
\.

\echo sequence update column: id
SELECT SETVAL('config.rule_max_fine_id_seq', (SELECT MAX(id) FROM config.rule_max_fine));
