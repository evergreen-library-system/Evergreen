COPY actor.usr_activity (id, usr, etype, event_time, event_data) FROM stdin;
23	1	17	2021-08-04 09:27:19.495139-05	\N
110	1	26	2022-06-17 15:51:18.092677-05	\N
\.

\echo sequence update column: id
SELECT SETVAL('actor.usr_activity_id_seq', (SELECT MAX(id) FROM actor.usr_activity));
