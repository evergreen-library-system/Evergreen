COPY permission.grp_tree (id, name, parent, usergroup, perm_interval, description, application_perm, hold_priority) FROM stdin;
16	Patron - Student	2	1	1 year	No overdue fines	\N	0
17	Patron - Homebound	2	1	2 years	No overdue fines	\N	0
18	Patron - Digital Only	2	1	5 years	No checkouts of physical materials	\N	0
19	Patron - Restricted	2	1	3 years	Limited to 2 concurrent checkouts	\N	0
\.

\echo sequence update column: id
SELECT SETVAL('permission.grp_tree_id_seq', (SELECT MAX(id) FROM permission.grp_tree));
