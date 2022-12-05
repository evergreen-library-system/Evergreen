COPY asset.uri (id, href, label, use_restriction, active) FROM stdin;
1	http://example.com/	Link text here	Public note here	1
8	http://example.com/ebookapi/t/001	Click to access online	\N	1
9	http://example.com/ebookapi/t/002	Click to access online	\N	1
10	http://example.com/ebookapi/t/003	Click to access online	\N	1
11	http://example.com/ebookapi/t/004	Click to access online	\N	1
\.

\echo sequence update column: id
SELECT SETVAL('asset.uri_id_seq', (SELECT MAX(id) FROM asset.uri));
