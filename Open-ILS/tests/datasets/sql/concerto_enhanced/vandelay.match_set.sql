COPY vandelay.match_set (id, name, owner, mtype) FROM stdin;
1	Default Matchset	1	biblio
\.

\echo sequence update column: id
SELECT SETVAL('vandelay.match_set_id_seq', (SELECT MAX(id) FROM vandelay.match_set));
