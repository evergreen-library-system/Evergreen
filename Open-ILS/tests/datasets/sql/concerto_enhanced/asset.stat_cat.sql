COPY asset.stat_cat (id, owner, opac_visible, name, required, sip_field, sip_format, checkout_archive) FROM stdin;
1	1	1	Special Acquisition	0	\N		1
2	1	1	Local Author	0	\N		1
\.

\echo sequence update column: id
SELECT SETVAL('asset.stat_cat_id_seq', (SELECT MAX(id) FROM asset.stat_cat));
