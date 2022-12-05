COPY vandelay.queue (id, owner, name, complete, match_set) FROM stdin;
1	1	ready player two	1	\N
2	1	hobbit	1	\N
3	1	earwig	1	\N
4	1	city we became	1	\N
6	1	authoritiesfornewrecords	1	\N
8	1	Serials	0	\N
9	1	newqueue1	1	1
10	1	uploadqueue2	1	1
\.

\echo sequence update column: id
SELECT SETVAL('vandelay.queue_id_seq', (SELECT MAX(id) FROM vandelay.queue));
