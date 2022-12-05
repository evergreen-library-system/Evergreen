COPY booking.resource_attr_value (id, owner, attr, valid_value) FROM stdin;
1	108	1	HDMI
2	108	1	VGA
3	108	1	DVI
4	108	2	720P
5	108	2	1080P
6	107	3	Windows
7	107	3	MacOS
8	101	4	Bear
9	101	4	Dog
10	101	4	Cupcake
11	101	4	Large Cupcake
12	106	5	1 Person
13	106	5	2 People
14	108	7	Space Stone
15	108	7	Mind Stone
16	108	7	Reality Stone
17	108	7	Power Stone
18	108	7	Time Stone
19	108	7	Soul Stone
20	9	9	Police Box
21	111	9	X-Wing
22	105	9	Star Cruiser
23	102	9	Broom
24	2	8	Guitar
25	2	8	Violin
26	2	8	Ukulele 
\.

\echo sequence update column: id
SELECT SETVAL('booking.resource_attr_value_id_seq', (SELECT MAX(id) FROM booking.resource_attr_value));
