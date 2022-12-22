COPY asset.uri_call_number_map (id, uri, call_number) FROM stdin;
40	11	1757
41	10	1758
42	9	1759
43	8	1760
\.

\echo sequence update column: id
SELECT SETVAL('asset.uri_call_number_map_id_seq', (SELECT MAX(id) FROM asset.uri_call_number_map));
