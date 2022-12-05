COPY biblio.monograph_part (id, record, label, label_sortkey, deleted) FROM stdin;
1	84	DISC 1	disc0000000001	0
2	84	DISC 2	disc0000000002	0
3	84	DISC 3	disc0000000003	0
4	84	DISC 4	disc0000000004	0
5	53	DISC 1	disc0000000001	0
6	53	DISC 2	disc0000000002	0
7	53	DISC 3	disc0000000003	0
8	53	DISC 4	disc0000000004	0
\.

\echo sequence update column: id
SELECT SETVAL('biblio.monograph_part_id_seq', (SELECT MAX(id) FROM biblio.monograph_part));
