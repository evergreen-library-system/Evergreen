COPY asset.copy_template (id, owning_lib, creator, editor, create_date, edit_date, name, circ_lib, status, location, loan_duration, fine_level, age_protect, circulate, deposit, ref, holdable, deposit_amount, price, circ_modifier, circ_as_type, alert_message, opac_visible, floating, mint_condition) FROM stdin;
1	4	1	1	2022-01-26 09:42:07.695661-06	2022-01-26 09:42:07.695661-06	Periodicals that Circ	4	7	132	2	2	\N	1	0	0	1	\N	\N	serial	\N	\N	1	\N	1
2	4	1	1	2022-01-26 09:43:16.353587-06	2022-01-26 09:43:16.353587-06	Newspapers	4	7	136	2	2	\N	0	0	\N	0	\N	\N	serial	\N	\N	1	\N	1
3	5	1	1	2022-01-26 11:15:28.896785-06	2022-01-26 11:15:28.896785-06	Periodicals that Circ	5	7	134	2	2	\N	1	0	0	1	\N	\N	serial	\N	\N	1	\N	1
4	5	1	1	2022-01-26 12:51:35.488863-06	2022-01-26 12:51:35.488863-06	Genealogy	5	7	125	2	2	\N	0	0	1	0	\N	\N	reference	\N	\N	1	\N	1
5	6	1	1	2022-01-26 14:04:22.258296-06	2022-01-26 14:04:22.258296-06	Periodicals that Circ	6	7	133	2	2	\N	1	0	0	1	\N	\N	serial	\N	\N	1	\N	1
6	6	1	1	2022-01-26 14:06:59.18915-06	2022-01-26 14:06:59.18915-06	Newspapers	6	7	188	2	2	\N	0	0	1	0	\N	\N	serial	\N	\N	1	\N	1
\.

\echo sequence update column: id
SELECT SETVAL('asset.copy_template_id_seq', (SELECT MAX(id) FROM asset.copy_template));
