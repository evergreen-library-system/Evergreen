COPY vandelay.match_set_point (id, match_set, parent, bool_op, svf, tag, subfield, negate, quality, heading) FROM stdin;
1	1	\N	AND	\N	\N	\N	0	1	0
2	1	1	OR	\N	\N	\N	0	1	0
3	1	2	\N	\N	020	a	0	1	0
4	1	2	\N	\N	024	a	0	2	0
5	1	2	\N	\N	028	a	0	3	0
6	1	1	\N	item_type	\N	\N	0	16	0
\.

\echo sequence update column: id
SELECT SETVAL('vandelay.match_set_point_id_seq', (SELECT MAX(id) FROM vandelay.match_set_point));
