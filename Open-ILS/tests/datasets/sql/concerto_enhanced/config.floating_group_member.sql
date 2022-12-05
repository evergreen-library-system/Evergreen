COPY config.floating_group_member (id, floating_group, org_unit, stop_depth, max_depth, exclude) FROM stdin;
2	2	107	2	3	0
\.

\echo sequence update column: id
SELECT SETVAL('config.floating_group_member_id_seq', (SELECT MAX(id) FROM config.floating_group_member));
