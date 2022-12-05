COPY serial.stream (id, distribution, routing_label) FROM stdin;
1	1	BR1-Periodicals
2	2	BR1-Periodicals
3	3	BR1-Periodicals
4	4	BR1-Periodicals
5	5	BR1-Periodicals
6	6	BR1-Periodicals
7	7	BR1-Periodicals
8	8	BR1-Periodicals
9	9	BR1-Periodicals
10	10	BR1-Newspapers
11	11	BR2-Magazines
12	12	BR2-Magazines
13	13	BR2-Magazines
14	14	BR2-Magazines
15	15	BR2-Magazines
16	16	BR2-Magazines
17	17	BR2-Magazines
18	18	BR2-Magazines
19	19	BR2-Genealogy
20	20	BR2-Magazines
21	21	BR2-Magazines
22	22	BR3-Newspapers
23	23	BR3-Periodicals
24	24	BR3-Periodicals
25	25	BR3-Periodicals
26	26	BR3-Periodicals
27	27	BR3-Periodicals
28	28	BR3-Periodicals
\.

\echo sequence update column: id
SELECT SETVAL('serial.stream_id_seq', (SELECT MAX(id) FROM serial.stream));
