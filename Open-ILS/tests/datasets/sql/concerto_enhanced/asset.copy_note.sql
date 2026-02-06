COPY asset.copy_note (id, owning_copy, creator, create_date, pub, title, value) FROM stdin;
1	4789	1	2021-11-23 17:22:30.277039-05	1	Laptop	Gray Laptop
2	1039	1	2021-11-23 17:25:46.536096-05	1	Damage	Item has Damage on last two pages. 
\.

\echo sequence update column: id
SELECT SETVAL('asset.copy_note_id_seq', (SELECT MAX(id) FROM asset.copy_note));
