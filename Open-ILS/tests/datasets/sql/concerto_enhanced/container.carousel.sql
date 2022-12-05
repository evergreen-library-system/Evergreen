COPY container.carousel (id, type, owner, name, bucket, creator, editor, create_time, edit_time, age_filter, owning_lib_filter, copy_location_filter, last_refresh_time, active, max_items) FROM stdin;
1	2	1	New Items at All Locations	1	1	1	2021-08-25 15:06:11-05	2021-08-25 15:10:09-05	5 years	{4,5,6,7,8,9,102,103,106,112,111,113,108,109,110}	\N	2022-07-06 05:05:01.55426-05	1	50
2	2	101	New Items at Leilholm Public Library	2	1	1	2021-08-25 15:13:38-05	2021-08-25 15:21:43-05	5 years	{102,103,101}	\N	2022-07-06 05:05:01.56904-05	1	50
3	4	4	Top Circulated Titles at West Emnet Public Library	3	1	1	2021-08-25 15:14:40-05	2021-08-25 15:18:27-05	5 years	{}	\N	2022-07-06 05:05:01.524371-05	1	50
4	3	6	Recently Returned Items at Hobbiton Public Library	4	1	1	2021-08-25 15:20:20-05	2021-08-25 15:20:20-05	1 year	{6}	\N	2022-07-06 05:05:01.53891-05	1	50
5	1	1	Staff Recommendations	6	1	1	2021-08-25 15:23:49-05	2021-08-25 15:24:16.615879-05	\N	\N	\N	\N	1	5
6	1	7	Music Books and Scores at Bree Public Library	8	1	1	2021-08-25 15:42:36-05	2021-08-25 15:44:06.338905-05	\N	\N	\N	\N	1	12
\.

\echo sequence update column: id
SELECT SETVAL('container.carousel_id_seq', (SELECT MAX(id) FROM container.carousel));
