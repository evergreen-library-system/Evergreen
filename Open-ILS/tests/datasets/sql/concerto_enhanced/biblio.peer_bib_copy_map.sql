COPY biblio.peer_bib_copy_map (id, peer_type, peer_record, target_copy) FROM stdin;
1	101	24	3105
2	101	93	3105
3	101	97	3105
4	101	100	3105
\.

\echo sequence update column: id
SELECT SETVAL('biblio.peer_bib_copy_map_id_seq', (SELECT MAX(id) FROM biblio.peer_bib_copy_map));
