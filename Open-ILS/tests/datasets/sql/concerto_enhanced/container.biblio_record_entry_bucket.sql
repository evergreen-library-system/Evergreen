COPY container.biblio_record_entry_bucket (id, owner, name, btype, description, pub, owning_lib, create_time) FROM stdin;
1	1	System-generated bucket for carousel: 1	carousel	\N	1	1	2021-08-25 16:06:12.180112-04
2	1	System-generated bucket for carousel: 2	carousel	\N	1	101	2021-08-25 16:13:39.1702-04
3	1	System-generated bucket for carousel: 3	carousel	\N	1	4	2021-08-25 16:14:40.911099-04
4	1	System-generated bucket for carousel: 4	carousel	\N	1	6	2021-08-25 16:20:20.820251-04
5	1	Staff Recommendations	staff_client		0	\N	2021-08-25 16:22:52.972578-04
6	1	System-created bucket for carousel 5 copied from bucket 5	carousel	\N	1	4	2021-08-25 16:23:49.880186-04
7	1	Music Books and Scores at Bree Public Library	staff_client		1	\N	2021-08-25 16:38:30-04
8	1	System-created bucket for carousel 6 copied from bucket 7	carousel	\N	1	4	2021-08-25 16:42:36.120041-04
13	1	Cello items	staff_client		0	\N	2021-11-29 16:08:46.881103-05
\.

\echo sequence update column: id
SELECT SETVAL('container.biblio_record_entry_bucket_id_seq', (SELECT MAX(id) FROM container.biblio_record_entry_bucket));
