COPY actor.org_unit (id, parent_ou, ou_type, ill_address, holds_address, mailing_address, billing_address, shortname, name, email, phone, opac_visible, fiscal_calendar, staff_catalog_visible) FROM stdin;
2	1	2	2	2	2	13	RPLS	Rohan Public Library System	\N	541-374-9696	1	1	1
3	1	2	3	3	3	19	SPLS	Shire Public Library System	hobbiton@example.com	706-663-6842	1	1	1
4	2	3	5	5	4	14	RPLS-WEPL	West Emnet Public Library	wepl@example.com	541-386-0202	1	1	1
5	2	3	8	8	6	7	RPLS-HDPL	Helm's Deep Public Library	hdpl@example.com	541-374-9696	1	1	1
6	3	3	9	9	9	9	SPLS-HPL	Hobbiton Public Library	hobbiton@example.com	706-663-6842	1	1	1
7	3	3	12	24	10	11	SPLS-BPL	Bree Public Library	bree@example.com	706-845-1699	1	1	1
8	4	4	18	16	17	15	RPLS-EHL	Edoras History Library	edoras@example.com	541-386-8585	1	1	1
9	6	5	23	21	22	20	SPLS-BKM	Shire Public Library System Bookmobile	shirebkm@example.com	706-663-6842	1	1	1
101	1	2	\N	\N	\N	25	LPLS	Leilholm Public Library	\N	508-799-3636	1	1	1
102	101	3	29	27	28	26	LPLS-GOD	Godric's Hollow Library	ghlib@example.com	508-799-3636	1	1	1
103	101	3	33	31	32	41	LPLS-WIL	Wiltshire Library	willib@example.com	505-835-8484	1	1	1
104	1	2	36	34	35	37	SMALL	Smallville Public Library System	small@example.com	620-663-0101	1	1	1
105	1	2	\N	\N	39	38	HHPL	Happy Harbor Public Library	HHPL@example.com	401-364-9999	1	1	1
106	105	3	44	42	43	40	HHPL-HHPL	Happy Harbor Public Library - Main Library	hhpl@example.com	401-364-9999	1	1	1
107	1	2	\N	\N	\N	45	WAKA	Wakanda Public Library System	WPL@example.com	573-346-9516	1	1	1
108	107	3	49	47	48	46	WAKA-MAIN	Wakanda Public Library - Main 	WPL@example.com	573-346-9516	1	1	1
109	108	4	\N	\N	\N	50	WAKA-BKM	Woonerf Bookmobile	wakabkm@example.com	573-346-9516	1	1	1
110	108	4	54	52	53	51	WAKA-TML	T'Chaka Memorial Library	tchaka@example.com	573-346-9517	1	1	1
111	107	3	58	56	57	55	WAKA-LVL	Lake Victoria Library	lvictoria@example.com	573-348-9875	1	1	1
112	107	3	62	60	61	59	WAKA-LTL	Lake Turkana Library	lturkana@example.com	573-693-1254	1	1	1
113	107	3	66	64	65	63	WAKA-BZPL	Birnin Zana Public Library	binin@example.com	573-374-6519	1	1	1
114	104	3	68	70	69	67	SMALL-SMALL	City Library	small@example.com	620-663-0101	1	1	1
\.

\echo sequence update column: id
SELECT SETVAL('actor.org_unit_id_seq', (SELECT MAX(id) FROM actor.org_unit));
