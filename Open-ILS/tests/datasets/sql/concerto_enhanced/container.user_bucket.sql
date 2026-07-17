COPY container.user_bucket (id, owner, name, btype, description, pub, owning_lib, create_time) FROM stdin;
1	1	Cello	hold_subscription	Cello players	1	108	2021-11-22 09:48:49.763846-05
2	1	Knitting Club	staff_client		0	\N	2022-06-17 16:16:13.754557-04
3	1	Board Members	staff_client		0	\N	2022-06-17 16:16:50.598178-04
\.

\echo sequence update column: id
SELECT SETVAL('container.user_bucket_id_seq', (SELECT MAX(id) FROM container.user_bucket));
