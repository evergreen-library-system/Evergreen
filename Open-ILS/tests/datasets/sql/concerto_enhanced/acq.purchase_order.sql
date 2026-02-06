COPY acq.purchase_order (id, owner, creator, editor, ordering_agency, create_time, edit_time, provider, state, order_date, name, cancel_reason, prepayment_required) FROM stdin;
1	1	1	1	4	2020-10-27 10:26:51.426709-04	2020-10-27 10:26:51.426709-04	1	pending	\N	1	\N	0
2	1	1	1	4	2020-10-27 10:26:51.426709-04	2020-10-27 10:26:51.426709-04	2	on-order	2020-10-27 10:26:51.426709-04	2	\N	0
3	1	1	1	107	2022-06-17 11:28:17.626762-04	2022-06-17 11:28:17.626762-04	2	pending	\N	3	\N	0
4	1	1	1	107	2022-06-17 11:33:21-04	2022-06-17 11:45:56.816962-04	1	on-order	2022-06-17 11:45:56.816962-04	April order	\N	0
5	1	1	1	105	2022-06-17 11:59:55-04	2022-06-17 12:00:28.935231-04	5	on-order	2022-06-17 12:00:28.935231-04	5	\N	0
\.

\echo sequence update column: id
SELECT SETVAL('acq.purchase_order_id_seq', (SELECT MAX(id) FROM acq.purchase_order));
