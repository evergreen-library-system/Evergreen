COPY config.circ_limit_set (id, name, owning_lib, items_out, depth, global, description) FROM stdin;
1	Software Limits	1	5	0	1	Limit concurent video game and software checkouts to 5
2	Bestseller Limits	1	10	0	1	Limit bestseller checkouts to 10 concurrent
3	New Books Limit	101	5	0	1	Limit LPLS new books to 5
4	Audiobooks Limit	107	10	0	1	Limit WAKA audiobooks to 10
\.

\echo sequence update column: id
SELECT SETVAL('config.circ_limit_set_id_seq', (SELECT MAX(id) FROM config.circ_limit_set));
