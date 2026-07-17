COPY acq.fund_transfer (id, src_fund, src_amount, dest_fund, dest_amount, transfer_time, transfer_user, note, funding_source_credit) FROM stdin;
1	13	125.00	14	125.00	2022-06-17 11:54:49.956568-04	1	\N	2
\.

\echo sequence update column: id
SELECT SETVAL('acq.fund_transfer_id_seq', (SELECT MAX(id) FROM acq.fund_transfer));
