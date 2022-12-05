COPY config.rule_recurring_fine (id, name, high, normal, low, recurrence_interval, grace_period) FROM stdin;
101	no_fines	0.00	0.00	0.00	1 day	1 day
\.

\echo sequence update column: id
SELECT SETVAL('config.rule_recurring_fine_id_seq', (SELECT MAX(id) FROM config.rule_recurring_fine));
