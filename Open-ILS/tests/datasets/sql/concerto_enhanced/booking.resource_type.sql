COPY booking.resource_type (id, name, elbow_room, fine_interval, fine_amount, max_fine, owner, catalog_item, transferable, record) FROM stdin;
1	Kobo Aura ONE ereader	\N	\N	0.00	\N	6	1	1	249
2	VeryPC Treeton Laptop	\N	\N	0.00	\N	6	1	1	250
3	Projector	1 day	1 day	10.00	100.00	108	0	0	\N
4	Library Use Laptop	00:15:00	01:00:00	1.00	20.00	107	0	1	\N
5	Cake Pan	2 days	1 day	0.10	3.00	101	0	1	\N
6	Kayak	3 days	1 day	20.00	200.00	106	0	0	\N
7	Kryptonite 	00:15:00	01:00:00	600.00	1800.00	114	0	0	\N
8	Fantastical Mode of Transportation	1 mon	7 days	500.00	25000.00	1	0	1	\N
9	Infinity Stones	00:10:00	\N	0.00	\N	108	0	0	\N
10	Musical Instruments	1 day	1 day	10.00	100.00	2	0	1	\N
11	Piano concertos nos. 17-22 : in full score, with Mozart's cadenzas for nos. 17-19, from the Breitkopf & Härtel complete works ed	\N	\N	0.00	\N	5	1	1	30
12	Piano concertos nos. 17-22 : in full score, with Mozart's cadenzas for nos. 17-19, from the Breitkopf & Härtel complete works ed	\N	1 day	0.10	3.00	7	1	0	30
13	Field guide to Flora and Fauna (No Return)	\N	\N	0.00	\N	1	0	0	\N
555	Meeting room	\N	\N	0.00	\N	1	0	1	\N
556	Phone charger	\N	\N	0.00	\N	3	0	1	\N
\.

\echo sequence update column: id
SELECT SETVAL('booking.resource_type_id_seq', (SELECT MAX(id) FROM booking.resource_type));
