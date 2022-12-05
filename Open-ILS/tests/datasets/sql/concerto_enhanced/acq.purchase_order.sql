COPY acq.purchase_order (id, owner, creator, editor, ordering_agency, create_time, edit_time, provider, state, order_date, name, cancel_reason, prepayment_required) FROM stdin;
1	1	1	1	4	2020-10-27 09:26:51.426709-05	2020-10-27 09:26:51.426709-05	1	pending	\N	1	\N	0
2	1	1	1	4	2020-10-27 09:26:51.426709-05	2020-10-27 09:26:51.426709-05	2	on-order	2020-10-27 09:26:51.426709-05	2	\N	0
3	1	1	1	107	2022-06-17 10:28:17.626762-05	2022-06-17 10:28:17.626762-05	2	pending	\N	3	\N	0
4	1	1	1	107	2022-06-17 10:33:21-05	2022-06-17 10:45:56.816962-05	1	on-order	2022-06-17 10:45:56.816962-05	April order	\N	0
5	1	1	1	105	2022-06-17 10:59:55-05	2022-06-17 11:00:28.935231-05	5	on-order	2022-06-17 11:00:28.935231-05	5	\N	0
\.

\echo sequence update column: id
SELECT SETVAL('acq.purchase_order_id_seq', (SELECT MAX(id) FROM acq.purchase_order));
