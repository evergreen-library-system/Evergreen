COPY actor.stat_cat (id, owner, name, opac_visible, usr_summary, sip_field, sip_format, checkout_archive, required, allow_freetext) FROM stdin;
2	1	Non-English Primary Language	0	0	\N		0	0	0
3	1	Wants to receive library newsletter	0	1	\N		0	0	0
4	101	Friends of the Library Member	1	1	\N		0	0	0
5	2	Book Club Member	1	1	\N		0	0	1
\.

\echo sequence update column: id
SELECT SETVAL('actor.stat_cat_id_seq', (SELECT MAX(id) FROM actor.stat_cat));
