COPY acq.provider (id, name, owner, currency_type, code, holding_tag, san, buyer_san, edi_default, active, prepayment_required, url, email, phone, fax_phone, default_copy_count, default_claim_policy, primary_contact) FROM stdin;
1	Ingram	1	USD	INGRAM	970	1697978	\N	\N	1	0	\N	\N	\N	\N	0	\N	\N
2	Brodart	2	USD	BRODART	970	1697684	\N	1	1	0	\N	\N	\N	\N	0	\N	\N
3	Baker & Taylor	1	USD	BT	970	3349659	\N	\N	1	0	\N	\N	\N	\N	0	\N	\N
4	Initech	4	USD	IT	970	1001001	\N	2	1	0	\N	\N	\N	\N	0	\N	\N
5	Overdrive	105	USD	OVERDRIVE	\N	\N	\N	\N	1	0	\N	\N	\N	\N	1	\N	\N
\.

\echo sequence update column: id
SELECT SETVAL('acq.provider_id_seq', (SELECT MAX(id) FROM acq.provider));
