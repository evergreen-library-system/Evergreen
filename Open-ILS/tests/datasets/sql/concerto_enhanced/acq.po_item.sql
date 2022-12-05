COPY acq.po_item (id, purchase_order, fund_debit, inv_item_type, title, author, note, estimated_cost, fund, target) FROM stdin;
1	5	218	BLA				1000.00	13	\N
\.

\echo sequence update column: id
SELECT SETVAL('acq.po_item_id_seq', (SELECT MAX(id) FROM acq.po_item));
