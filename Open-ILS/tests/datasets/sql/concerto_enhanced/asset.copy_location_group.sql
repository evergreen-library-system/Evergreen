COPY asset.copy_location_group (id, name, owner, pos, top, opac_visible) FROM stdin;
1	Juvenile Collection	2	0	0	1
2	Local Interest Collection	3	0	0	1
\.

\echo sequence update column: id
SELECT SETVAL('asset.copy_location_group_id_seq', (SELECT MAX(id) FROM asset.copy_location_group));
