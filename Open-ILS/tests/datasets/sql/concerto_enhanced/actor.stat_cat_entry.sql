COPY actor.stat_cat_entry (id, stat_cat, owner, value) FROM stdin;
15	2	1	Urdu
16	2	1	Punjabi
17	2	1	Chinese (Mandarin)
18	2	1	Chinese (Cantonese)
19	2	1	Amharic
20	2	1	German
21	2	1	Czech
22	2	1	French
23	2	1	Italian
24	2	1	Spanish
25	2	1	Vietnamese
26	2	1	Korean
27	2	1	Japanese
28	2	1	Other / Not Listed
29	3	1	Yes
30	3	1	No
31	4	101	Yes
32	4	101	No
\.

\echo sequence update column: id
SELECT SETVAL('actor.stat_cat_entry_id_seq', (SELECT MAX(id) FROM actor.stat_cat_entry));
