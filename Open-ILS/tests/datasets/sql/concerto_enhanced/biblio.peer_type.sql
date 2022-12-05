COPY biblio.peer_type (id, name) FROM stdin;
101	Media player
\.

\echo sequence update column: id
SELECT SETVAL('biblio.peer_type_id_seq', (SELECT MAX(id) FROM biblio.peer_type));
