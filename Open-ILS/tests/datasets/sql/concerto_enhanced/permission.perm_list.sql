COPY permission.perm_list (id, code, description) FROM stdin;
480	VIEW_STANDING_PENALTY	VIEW_STANDING_PENALTY
\.

\echo sequence update column: id
SELECT SETVAL('permission.perm_list_id_seq', (SELECT MAX(id) FROM permission.perm_list));
