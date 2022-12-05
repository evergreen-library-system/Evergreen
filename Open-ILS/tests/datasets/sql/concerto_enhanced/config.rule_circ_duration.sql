COPY config.rule_circ_duration (id, name, extended, normal, shrt, max_renewals, max_auto_renewals) FROM stdin;
101	audiobook	14 days	21 days	7 days	1	2
102	bestseller	21 days	14 days	7 days	0	0
103	book	21 days	21 days	21 days	2	2
105	book_new	21 days	14 days	7 days	1	1
106	cd_music	21 days	14 days	7 days	1	1
107	equipment	7 days	3 days	1 day	1	0
108	gov_doc	28 days	21 days	14 days	1	1
109	kit	21 days	14 days	7 days	1	1
110	media	21 days	14 days	7 days	1	1
111	realia	21 days	14 days	7 days	1	1
112	serial	21 days	14 days	7 days	1	1
113	software	21 days	14 days	7 days	1	1
115	special_collections	14 days	7 days	3 days	0	0
116	videodisc	14 days	7 days	3 days	1	1
117	videogame	14 days	7 days	7 days	1	1
\.

\echo sequence update column: id
SELECT SETVAL('config.rule_circ_duration_id_seq', (SELECT MAX(id) FROM config.rule_circ_duration));
