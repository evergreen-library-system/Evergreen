COPY acq.invoice_item (id, invoice, purchase_order, fund_debit, inv_item_type, title, author, note, cost_billed, actual_cost, fund, amount_paid, po_item, target) FROM stdin;
1	1	\N	217	PRO	\N	\N	\N	3.88	\N	14	3.88	\N	\N
2	2	\N	\N	SHP	\N	\N	\N	3.29	\N	\N	3.29	\N	\N
3	3	5	219	BLA	\N	\N		23.88	\N	13	23.88	1	\N
4	4	5	220	BLA	\N	\N		82.00	\N	13	82.00	1	\N
\.

\echo sequence update column: id
SELECT SETVAL('acq.invoice_item_id_seq', (SELECT MAX(id) FROM acq.invoice_item));
