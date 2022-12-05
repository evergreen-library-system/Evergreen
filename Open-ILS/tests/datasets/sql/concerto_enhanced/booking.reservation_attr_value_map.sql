COPY booking.reservation_attr_value_map (id, reservation, attr_value) FROM stdin;
1	487	1
2	487	5
3	489	15
4	490	14
5	491	16
6	492	17
7	493	18
8	494	19
9	495	13
10	496	12
11	499	24
\.

\echo sequence update column: id
SELECT SETVAL('booking.reservation_attr_value_map_id_seq', (SELECT MAX(id) FROM booking.reservation_attr_value_map));
