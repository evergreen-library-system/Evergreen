COPY acq.invoice_entry (id, invoice, purchase_order, lineitem, inv_item_count, phys_item_count, note, billed_per_item, cost_billed, actual_cost, amount_paid) FROM stdin;
1	1	4	59	1	1	\N	\N	20.99	\N	20.99
2	1	4	71	1	1	\N	\N	19.99	\N	19.99
3	1	4	61	1	1	\N	\N	16.32	\N	16.32
4	1	4	60	1	1	\N	\N	19.97	\N	19.97
5	2	4	69	1	1	\N	\N	19.99	\N	19.99
6	2	4	79	1	1	\N	\N	19.99	\N	19.99
7	2	4	78	1	1	\N	\N	19.97	\N	19.97
\.

\echo sequence update column: id
SELECT SETVAL('acq.invoice_entry_id_seq', (SELECT MAX(id) FROM acq.invoice_entry));
