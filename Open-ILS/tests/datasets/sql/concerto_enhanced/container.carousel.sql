COPY container.carousel (id, type, owner, name, bucket, creator, editor, create_time, edit_time, age_filter, owning_lib_filter, copy_location_filter, last_refresh_time, active, max_items) FROM stdin;
1	2	1	New Items at All Locations	1	1	1	2021-08-25 16:06:11-04	2021-08-25 16:10:09-04	5 years	{4,5,6,7,8,9,102,103,106,112,111,113,108,109,110}	\N	2022-07-06 06:05:01.55426-04	1	50
2	2	101	New Items at Leilholm Public Library	2	1	1	2021-08-25 16:13:38-04	2021-08-25 16:21:43-04	5 years	{102,103,101}	\N	2022-07-06 06:05:01.56904-04	1	50
3	4	4	Top Circulated Titles at West Emnet Public Library	3	1	1	2021-08-25 16:14:40-04	2021-08-25 16:18:27-04	5 years	{}	\N	2022-07-06 06:05:01.524371-04	1	50
4	3	6	Recently Returned Items at Hobbiton Public Library	4	1	1	2021-08-25 16:20:20-04	2021-08-25 16:20:20-04	1 year	{6}	\N	2022-07-06 06:05:01.53891-04	1	50
5	1	1	Staff Recommendations	6	1	1	2021-08-25 16:23:49-04	2021-08-25 16:24:16.615879-04	\N	\N	\N	\N	1	5
6	1	7	Music Books and Scores at Bree Public Library	8	1	1	2021-08-25 16:42:36-04	2021-08-25 16:44:06.338905-04	\N	\N	\N	\N	1	12
\.

\echo sequence update column: id
SELECT SETVAL('container.carousel_id_seq', (SELECT MAX(id) FROM container.carousel));
