COPY actor.org_address (id, valid, address_type, org_unit, street1, street2, city, county, state, country, post_code, san, latitude, longitude) FROM stdin;
1	1	MAILING	1	123 Main St.	\N	Anywhere	\N	GA	US	30303	\N	\N	\N
2	1	MAILING	2	531 Chedder Gorge	\N	Helm's Deep	\N	OR	US	97014	\N	\N	\N
3	1	MAILING	3	103 Bywater Rd	\N	Hobbiton	\N	GA	US	31822	\N	\N	\N
4	1	MAILING	4	2015 East Marina Way	123 Main St.	West Emnet	\N	OR	US	97031	\N	\N	\N
5	1	MAILING	4	2015 East Marina Way		West Emnet	\N	OR	US	97031	\N	\N	\N
6	1	MAILING	5	BR2	234 Side St.	Anywhere	\N	GA	US	30304	\N	\N	\N
7	1	MAILING	5	531 Chedder Gorge		Helm's Deep	\N	OR	US	97014	\N	45.68241	-121.77216
8	1	MAILING	5	531 Chedder Gorge		Helm's Deep	\N	OR	US	97014	\N	\N	\N
9	1	MAILING	6	103 Bywater Rd		Hobbiton	\N	GA	US	31822	\N	32.813352	-84.695027
10	1	MAILING	7	207 Great East Road		Bree	\N	GA	US	31826	\N	\N	\N
11	1	MAILING	7	207 Great East Road		Bree	\N	GA	US	31826	\N	32.813352	-84.695027
12	1	MAILING	7	207 Great East Road		Bree		GA	US	31826	\N	\N	\N
13	0	MAILING	2	531 Chedder Gorge	\N	Helm's Deep	\N	OR	US	97014	\N	\N	\N
14	0	MAILING	4	2015 East Marina Way		West Emnet	\N	OR	US	97031	\N	45.701186	-121.524223
15	0	PHYSICAL	8	502 State Street	\N	West Emnet	\N	OR	US	97031	\N	45.992695	-123.920372
16	0	HOLDS	8	2015 East Marina Way	HOLDS  - EDORAS	West Emnet	\N	OR	US	97031	\N	\N	\N
17	0	MAILING	8	2015 East Marina Way	Edoras History Library	West Emnet	\N	OR	US	97031	\N	\N	\N
18	0	ILL	8	2015 East Marina Way	ILL DEPARTMENT - EDORAS	West Emnet	\N	OR	US	97031	\N	\N	\N
19	0	MAILING	3	103 Bywater Rd	\N	Hobbiton	\N	GA	US	31822	\N	\N	\N
20	0	MAILING	9	103 Bywater Rd	\N	Hobbiton		GA	United States	31822	\N	\N	\N
21	0	MAILING	9	103 Bywater Rd 	\N	Hobbiton	\N	GA	US	31822	\N	\N	\N
22	0	MAILING	9	103 Bywater Rd	\N	Hobbiton		GA	United States	31822	\N	\N	\N
23	0	MAILING	9	103 Bywater Rd	\N	Hobbiton		GA	United States	31822	\N	\N	\N
24	0	MAILING	7	207 Great East Road		Bree		GA	US	31826	\N	\N	\N
25	0	MAILING	101	87 Landcaster Rd	\N	Godric's Hollow	\N	MA	US	01603	\N	\N	\N
26	0	MAILING	102	87 Landcaster Rd	\N	Godric's Hollow		MA	United States	01603	\N	42.05623	-71.469374
27	0	MAILING	102	87 Landcaster Rd	Holds	Godric's Hollow		MA	United States	01603	\N	\N	\N
28	0	MAILING	102	87 Landcaster Rd	\N	Godric's Hollow		MA	United States	01603	\N	\N	\N
29	0	MAILING	102	87 Landcaster Rd	ILL Department	Godric's Hollow		MA	United States	01603	\N	\N	\N
30	0	MAILING	103	15 High St	\N	Wiltshire	\N	MA	US	01583	\N	\N	\N
31	0	MAILING	103	15 High St	HOLDS	Wiltshire	\N	MA	US	01583	\N	\N	\N
32	0	Mailing	103	15 High St	\N	Wiltshire	\N	MA	US	01583	\N	\N	\N
33	0	MAILING	103	15 High St	ILL Department	Wiltshire	\N	MA	US	01583	\N	\N	\N
34	0	MAILING	104	901 Jefferson Ave	\N	Smallville	\N	KS	US	67501	\N	\N	\N
35	0	MAILING	104	901 Jefferson Ave	\N	Smallville	\N	KS	US	67501	\N	\N	\N
36	0	MAILING	104	901 Jefferson Ave	\N	Smallville	\N	KS	US	67501	\N	\N	\N
37	0	MAILING	104	901 Jefferson Ave	\N	Smallville	\N	KS	US	67501	\N	38.06284	-97.9374
38	0	Mailing	105	52 Post Road		Happy Harbor	\N	RI	USA	02813	\N	41.383955	-71.638351
39	0	Mailing	105	52 Post Road	\N	Happy Harbor	\N	RI	USA	02813	\N	\N	\N
40	0	Physical	106	52 Post Rd	\N	Happy Harbor	\N	RI	USA	02813	\N	41.383955	-71.638351
41	0	MAILING	103	15 High St	\N	Wiltshire	MA	MA	US	01583	\N	42.38913	-71.79801
42	0	Holds	106	52 Post Road	HOLDS	Happy Harbor	\N	RI	US	02813	\N	\N	\N
43	0	Mailing	106	52 Post Road	\N	Happy Harbor	\N	RI	US	02813	\N	\N	\N
44	0	ILL	106	52 Post Road	ILL DEPARTMENT	Happy Harbor`	\N	RI	US	02813	\N	\N	\N
45	0	Mailing	107	345 Lumumba St	\N	Wakanda	\N	MO	US	65020	\N	\N	\N
46	0	Physical	108	345 Lumumba St	\N	Wakanda 	\N	MO	US	65020	\N	38.005186	-92.744503
47	0	Mailing	108	345 Lumumba St	HOLDS	Wakanda	\N	MO	US	65020	\N	\N	\N
48	0	Mailing	108	345 Lumumba St	\N	Wakanda	\N	MO	US	65020	\N	\N	\N
49	0	Mailing	108	345 Lumumba St	ILL Department	Wakanda	\N	MO	US	65020	\N	\N	\N
50	0	Physical	109	345 Lumumba St	\N	Wakanda	\N	MO	US	65020	\N	\N	\N
51	0	Physical	110	454 Tshombe Rd	Physical Address	Wakanda	\N	MO	US	65020	\N	38.008251	-92.744237
52	0	Holds	110	PO Box 454	HOLDS	Wakanda	\N	MO	US	65020	\N	\N	\N
53	0	Mailing	110	PO Box 454	Mailing Address	Wakanda	\N	MO	US	65020	\N	\N	\N
54	0	ILL	110	PO Box 454	ILL Department	Wakanda	\N	MO	US	65020	\N	\N	\N
55	0	Physical	111	857 Mukwano Road	\N	Kampala	\N	MO	US	65065	\N	38.123792	-92.666664
56	0	Mailing	111	857 Mukwano Road	HOLDS	Kampala	\N	MO	US	65065	\N	\N	\N
57	0	Mailing	111	857 Mukwano Road	\N	Kampala	\N	MO	US	65065	\N	\N	\N
58	0	ILL	111	857 Mukwano Road	ILL Department	Kampala	\N	MO	US	65065	\N	\N	\N
59	0	Physical	112	6767 North St	\N	Sibiloi	\N	MO	US	65026	\N	38.344428	-92.580894
60	0	Holds	112	6767 North St	HOLDS	Sibiloi	\N	MO	US	65026	\N	\N	\N
61	0	Mailing	112	6767 North St	\N	Sibiloi	\N	MO	US	65026	\N	\N	\N
62	0	ILL	112	6767 North St	ILL Department	Sibiloi	\N	MO	US	65026	\N	\N	\N
63	0	Physical	113	450 Shinkolobwe Court	\N	Birnin Zana	\N	MO	US	65037	\N	38.205337	-92.835008
64	0	Holds	113	450 Shinkolobwe Court	HOLDS	Birnin Zana	\N	MO	US	65037	\N	\N	\N
65	0	Mailing	113	450 Shinkolobwe Court	\N	Birnin Zana	\N	MO	US	65037	\N	\N	\N
66	0	ILL	113	450 Shinkolobwe Court	ILL Department	Birnin Zana	\N	MO	US	65037	\N	\N	\N
67	1	Physical	114	901 Jefferson Ave	\N	Smallville	\N	KS	USA	67501	\N	38.06284	-97.9374
68	1	ILL	114	901 Jefferson Ave	\N	Smallville	\N	KS	USA	67501	\N	38.06284	-97.9374
69	0	Mailing	114	901 Jefferson Ave	\N	Smallville	\N	KS	USA	67501	\N	38.06284	-97.9374
70	0	Holds	114	901 Jefferson Ave	\N	Smallville	\N	KS	USA	67501	\N	38.06284	-97.9374
\.

\echo sequence update column: id
SELECT SETVAL('actor.org_address_id_seq', (SELECT MAX(id) FROM actor.org_address));
