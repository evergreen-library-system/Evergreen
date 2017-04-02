--
-- PostgreSQL database dump
--

SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

SET search_path = query, pg_catalog;

--
-- Name: case_branch_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('case_branch_id_seq', 3, true);


--
-- Name: expression_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('expression_id_seq', 60, true);


--
-- Name: from_relation_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('from_relation_id_seq', 10, true);


--
-- Name: function_param_def_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('function_param_def_id_seq', 1, false);


--
-- Name: function_sig_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('function_sig_id_seq', 6, true);


--
-- Name: order_by_item_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('order_by_item_id_seq', 4, true);


--
-- Name: query_sequence_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('query_sequence_id_seq', 4, true);


--
-- Name: record_column_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('record_column_id_seq', 1, false);


--
-- Name: select_item_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('select_item_id_seq', 47, true);


--
-- Name: stored_query_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('stored_query_id_seq', 25, true);


--
-- Name: subfield_id_seq; Type: SEQUENCE SET; Schema: query; Owner: evergreen
--

SELECT pg_catalog.setval('subfield_id_seq', 1, false);


--
-- Data for Name: bind_variable; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE bind_variable DISABLE TRIGGER ALL;

COPY bind_variable (name, type, description, default_value, label) FROM stdin;
shortname	string	org unit shortname	"BR3"	lib shortname
O'Leary	string	Ireland's kind of name	"O'Bryan"	nom d'Eire
ou	number	org unit	\N	lib
\.


ALTER TABLE bind_variable ENABLE TRIGGER ALL;

--
-- Data for Name: case_branch; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE case_branch DISABLE TRIGGER ALL;

COPY case_branch (id, parent_expr, seq_no, condition, result) FROM stdin;
2	53	2	54	56
3	53	3	\N	57
1	53	1	58	55
\.


ALTER TABLE case_branch ENABLE TRIGGER ALL;

--
-- Data for Name: expression; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE expression DISABLE TRIGGER ALL;

COPY expression (id, type, parenthesize, parent_expr, seq_no, literal, table_alias, column_name, left_operand, operator, right_operand, function_id, subquery, cast_type, negate, bind_variable) FROM stdin;
1	xbool	f	\N	1	TRUE	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
2	xcol	f	\N	1	\N	aou	id	\N	\N	\N	\N	\N	\N	f	\N
3	xcol	f	\N	1	\N	aou	name	\N	\N	\N	\N	\N	\N	f	\N
4	xcol	f	\N	1	\N	aou	shortname	\N	\N	\N	\N	\N	\N	f	\N
5	xcol	f	\N	1	\N	aou	parent_ou	\N	\N	\N	\N	\N	\N	f	\N
6	xnum	f	\N	1	3	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
7	xop	f	\N	1	\N	\N	\N	5	>	6	\N	\N	\N	f	\N
8	xop	f	\N	1	\N	\N	\N	2	=	6	\N	\N	\N	f	\N
9	xsubq	f	\N	1	\N	\N	\N	\N	\N	\N	\N	3	\N	f	\N
10	xcol	f	\N	1	\N	aout	id	\N	\N	\N	\N	\N	\N	f	\N
11	xin	f	\N	1	\N	\N	\N	10	\N	\N	\N	3	\N	f	\N
12	xcol	f	\N	1	\N	aou	ou_type	\N	\N	\N	\N	\N	\N	f	\N
13	xcol	f	\N	1	\N	au	id	\N	\N	\N	\N	\N	\N	f	\N
14	xop	f	\N	1	\N	\N	\N	13	=	12	\N	\N	\N	f	\N
15	xex	f	\N	1	\N	\N	\N	\N	\N	\N	\N	3	\N	f	\N
16	xcol	f	\N	1	\N	aou	\N	\N	\N	\N	\N	\N	\N	f	\N
17	xbind	f	\N	1	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	ou
18	xop	f	\N	1	\N	\N	\N	2	=	17	\N	\N	\N	f	\N
19	xcol	f	\N	1	\N	aou	opac_visible	\N	\N	\N	\N	\N	\N	f	\N
20	xbind	f	\N	1	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	shortname
21	xop	f	\N	1	\N	\N	\N	4	=	20	\N	\N	\N	f	\N
23	xcol	f	\N	1	\N	aou	email	\N	\N	\N	\N	\N	\N	f	\N
24	xcol	f	\N	1	\N	aou	holds_address	\N	\N	\N	\N	\N	\N	f	\N
27	xser	f	\N	1	\N	\N	\N	\N	OR	\N	\N	\N	\N	f	\N
22	xisnull	f	27	1	\N	\N	\N	5	\N	\N	\N	\N	\N	f	\N
25	xisnull	f	27	2	\N	\N	\N	23	\N	\N	\N	\N	\N	f	\N
26	xisnull	f	27	3	\N	\N	\N	24	\N	\N	\N	\N	\N	f	\N
32	xin	f	\N	1	\N	\N	\N	5	\N	\N	\N	\N	\N	f	\N
29	xnum	f	32	1	1	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
30	xnum	f	32	2	3	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
31	xnum	f	32	3	6	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
33	xfunc	f	\N	1	\N	\N	\N	\N	\N	\N	1	\N	\N	f	\N
34	xcol	f	33	1	\N	aou	name	\N	\N	\N	\N	\N	\N	f	\N
35	xop	f	\N	1	\N	\N	\N	2	=	6	\N	\N	\N	f	\N
36	xfunc	f	\N	1	\N	\N	name	\N	\N	\N	2	\N	\N	f	\N
37	xcol	f	36	1	\N	aou	id	\N	\N	\N	\N	\N	\N	f	\N
38	xbet	f	\N	1	\N	\N	\N	5	\N	\N	\N	\N	\N	f	\N
39	xnum	f	38	1	1	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
40	xnum	f	38	2	4	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
41	xfunc	f	\N	1	\N	\N	\N	\N	\N	\N	3	\N	\N	f	\N
42	xstr	f	41	1	DOW	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
43	xcol	f	41	2	\N	au	create_date	\N	\N	\N	\N	\N	\N	f	\N
44	xfunc	f	\N	1	\N	\N	\N	\N	\N	\N	4	\N	\N	f	\N
45	xnum	f	44	1	1	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
46	xfunc	f	\N	1	\N	\N	\N	\N	\N	\N	1	\N	\N	f	\N
47	xstr	f	46	1	goober	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
48	xcol	f	\N	1	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
49	xfunc	f	\N	1	\N	\N	\N	\N	\N	\N	5	\N	\N	f	\N
50	xfunc	f	\N	1	\N	\N	\N	\N	\N	\N	6	\N	\N	f	\N
51	xstr	f	50	1	both	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
52	xcol	f	50	2	\N	au	usrname	\N	\N	\N	\N	\N	\N	f	\N
54	xnum	f	\N	1	2	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
55	xstr	f	\N	1	First	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
56	xstr	f	\N	1	Second	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
57	xstr	f	\N	1	Other	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
53	xcase	f	\N	1	\N	\N	\N	2	\N	\N	\N	\N	\N	f	\N
58	xnum	f	\N	1	1	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
59	xcast	f	\N	1	\N	\N	\N	2	\N	\N	\N	\N	13	f	\N
60	xnum	f	\N	1	100	\N	\N	\N	\N	\N	\N	\N	\N	f	\N
\.


ALTER TABLE expression ENABLE TRIGGER ALL;

--
-- Data for Name: from_relation; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE from_relation DISABLE TRIGGER ALL;

COPY from_relation (id, type, table_name, class_name, subquery, function_call, table_alias, parent_relation, seq_no, join_type, on_clause) FROM stdin;
1	RELATION	actor.org_unit	aou	\N	\N	aou	\N	1	\N	\N
2	RELATION	actor.org_unit_type	aout	\N	\N	aout	1	1	INNER	1
3	RELATION	actor.org_unit	aou	\N	\N	aou	\N	1	\N	\N
4	RELATION	actor.org_unit_type	aout	\N	\N	aout	\N	1	\N	\N
5	SUBQUERY	\N	\N	3	\N	aou	\N	1	\N	\N
6	RELATION	actor.usr	au	\N	\N	au	\N	1	\N	\N
7	SUBQUERY	\N	\N	3	\N	aou	6	1	INNER	14
8	RELATION	\N	aou	\N	\N	aou	\N	1	\N	\N
9	RELATION	actor.usr	au	\N	\N	au	\N	1	\N	\N
10	FUNCTION	\N	\N	\N	46	\N	\N	1	\N	\N
\.


ALTER TABLE from_relation ENABLE TRIGGER ALL;

--
-- Data for Name: function_param_def; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE function_param_def DISABLE TRIGGER ALL;

COPY function_param_def (id, function_id, seq_no, datatype) FROM stdin;
\.


ALTER TABLE function_param_def ENABLE TRIGGER ALL;

--
-- Data for Name: function_sig; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE function_sig DISABLE TRIGGER ALL;

COPY function_sig (id, function_name, return_type, is_aggregate) FROM stdin;
1	upper	13	f
2	actor.org_unit_ancestors	\N	f
4	COUNT	\N	t
5	CURRENT_DATE	19	f
3	EXTRACT	7	f
6	TRIM	13	f
\.


ALTER TABLE function_sig ENABLE TRIGGER ALL;

--
-- Data for Name: order_by_item; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE order_by_item DISABLE TRIGGER ALL;

COPY order_by_item (id, stored_query, seq_no, expression) FROM stdin;
3	10	1	5
4	10	2	2
\.


ALTER TABLE order_by_item ENABLE TRIGGER ALL;

--
-- Data for Name: query_sequence; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE query_sequence DISABLE TRIGGER ALL;

COPY query_sequence (id, parent_query, seq_no, child_query) FROM stdin;
3	2	1	1
4	2	2	1
\.


ALTER TABLE query_sequence ENABLE TRIGGER ALL;

--
-- Data for Name: record_column; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE record_column DISABLE TRIGGER ALL;

COPY record_column (id, from_relation, seq_no, column_name, column_type) FROM stdin;
\.


ALTER TABLE record_column ENABLE TRIGGER ALL;

--
-- Data for Name: select_item; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE select_item DISABLE TRIGGER ALL;

COPY select_item (id, stored_query, seq_no, expression, column_alias, grouped_by) FROM stdin;
1	1	1	2	id	f
2	1	2	3	name	f
3	1	3	4	short_name	f
6	4	2	9	\N	f
5	4	1	10	\N	f
7	5	1	10	\N	f
8	6	1	12	\N	f
4	3	1	12	\N	f
9	7	1	12	goober	f
10	8	1	10	\N	f
11	9	1	16	\N	f
12	10	1	2	id	f
13	10	2	5	parent	f
14	10	3	4	short_name	f
15	11	1	2	id	f
16	12	1	2	\N	f
17	12	2	3	\N	f
18	12	3	4	\N	f
19	12	4	19	\N	f
20	12	5	5	\N	f
21	13	1	2	\N	f
22	13	2	3	\N	f
23	13	3	4	\N	f
24	13	4	19	\N	f
25	13	5	5	\N	f
26	14	1	2	\N	f
27	15	1	2	id	f
28	16	1	2	id	f
29	17	1	2	id	f
30	17	2	3	name	f
31	17	3	33	name	f
32	18	1	2	id	f
33	18	2	3	id	f
34	18	4	36	root_name	f
35	19	1	2	id	f
36	20	1	13	id	f
37	20	2	41	create_day	f
39	21	2	44	how_many	f
38	21	1	5	parent	t
40	23	1	48	\N	f
41	22	1	44	how_many	f
42	22	2	5	parent	t
43	20	3	49	today	f
45	24	2	53	Branch sequence	f
46	24	1	2	id	f
47	25	1	59	cast_text	f
\.


ALTER TABLE select_item ENABLE TRIGGER ALL;

--
-- Data for Name: stored_query; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE stored_query DISABLE TRIGGER ALL;

COPY stored_query (id, type, use_all, use_distinct, from_clause, where_clause, having_clause, limit_count, offset_count) FROM stdin;
1	SELECT	f	f	1	7	\N	\N	\N
2	UNION	f	f	\N	\N	\N	\N	\N
3	SELECT	f	f	3	8	\N	\N	\N
4	SELECT	f	f	4	\N	\N	\N	\N
5	SELECT	f	f	4	11	\N	\N	\N
6	SELECT	f	f	5	\N	\N	\N	\N
7	SELECT	f	f	6	\N	\N	\N	\N
8	SELECT	f	f	4	15	\N	\N	\N
9	SELECT	f	f	3	\N	\N	\N	\N
10	SELECT	f	f	3	\N	\N	\N	\N
13	SELECT	f	f	8	21	\N	\N	\N
14	SELECT	f	f	3	22	\N	\N	\N
15	SELECT	f	f	3	27	\N	\N	\N
16	SELECT	f	f	3	32	\N	\N	\N
17	SELECT	f	f	3	32	\N	\N	\N
18	SELECT	f	f	3	35	\N	\N	\N
19	SELECT	f	f	3	38	\N	\N	\N
20	SELECT	f	f	9	\N	\N	\N	\N
21	SELECT	f	f	3	\N	\N	\N	\N
23	SELECT	f	f	10	\N	\N	\N	\N
22	SELECT	f	f	3	\N	\N	\N	\N
24	SELECT	f	f	3	\N	\N	\N	\N
25	SELECT	f	f	3	\N	\N	\N	\N
12	SELECT	f	f	8	18	\N	\N	\N
11	SELECT	f	f	8	\N	\N	60	58
\.


ALTER TABLE stored_query ENABLE TRIGGER ALL;

--
-- Data for Name: subfield; Type: TABLE DATA; Schema: query; Owner: evergreen
--

ALTER TABLE subfield DISABLE TRIGGER ALL;

COPY subfield (id, composite_type, seq_no, subfield_type) FROM stdin;
\.


ALTER TABLE subfield ENABLE TRIGGER ALL;

--
-- PostgreSQL database dump complete
--

