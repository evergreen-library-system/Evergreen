COPY booking.resource_attr (id, owner, name, resource_type, required) FROM stdin;
1	108	Connection Type	3	0
2	108	Resolution	3	0
3	107	OS	4	0
4	101	Pan Design	5	0
5	106	Capacity	6	0
6	1	Type	8	0
7	108	Stone Type	9	0
8	2	Instrument	10	0
9	1	Transport	8	0
\.

\echo sequence update column: id
SELECT SETVAL('booking.resource_attr_id_seq', (SELECT MAX(id) FROM booking.resource_attr));
