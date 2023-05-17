COPY asset.uri (id, href, label, use_restriction, active) FROM stdin;
8	http://example.com/ebookapi/t/001	Click to access online	\N	1
9	http://example.com/ebookapi/t/002	Click to access online	\N	1
10	http://example.com/ebookapi/t/003	Click to access online	\N	1
11	http://example.com/ebookapi/t/004	Click to access online	\N	1
12	http://ezproxy.uwindsor.ca/login?url=http://books.scholarsportal.info/viewdoc.html?id=/ebooks/ebooks2/springer/2011-04-14/2/3540095144	Available Online	\N	1
13	http://ezproxy.uwindsor.ca/login?url=http://dx.doi.org/10.1007/BFb0070997	Available Online	\N	1
14	http://librweb.laurentian.ca/login?url=http://dx.doi.org/10.1007/4-431-28775-2	http://librweb.laurentian.ca/login?url=http://dx.doi.org/10.1007/4-431-28775-2	Available online from SpringerLink	1
15	http://librweb.laurentian.ca/login?url=http://resolver.scholarsportal.info/isbn/9784431287759	http://librweb.laurentian.ca/login?url=http://resolver.scholarsportal.info/isbn/9784431287759	Available online from ScholarsPortal	1
16	http://librweb.laurentian.ca/login?url=http://dx.doi.org/10.1007/3-540-46145-0	http://librweb.laurentian.ca/login?url=http://dx.doi.org/10.1007/3-540-46145-0	Available online from SpringerLink	1
17	http://librweb.laurentian.ca/login?url=http://resolver.scholarsportal.info/isbn/9783540461456	http://librweb.laurentian.ca/login?url=http://resolver.scholarsportal.info/isbn/9783540461456	Available online from Scholars Portal	1
18	http://example.com/	Link text here	Public note here	1
\.

\echo sequence update column: id
SELECT SETVAL('asset.uri_id_seq', (SELECT MAX(id) FROM asset.uri));
