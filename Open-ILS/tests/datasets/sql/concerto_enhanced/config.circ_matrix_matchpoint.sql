COPY config.circ_matrix_matchpoint (id, active, org_unit, grp, circ_modifier, copy_location, marc_type, marc_form, marc_bib_level, marc_vr_format, copy_circ_lib, copy_owning_lib, user_home_ou, ref_flag, juvenile_flag, is_renewal, usr_age_lower_bound, usr_age_upper_bound, item_age, circulate, duration_rule, recurring_fine_rule, max_fine_rule, hard_due_date, renewals, grace_period, script_test, total_copy_hold_ratio, available_copy_hold_ratio, description, renew_extends_due_date, renew_extend_min_interval) FROM stdin;
2	0	2	2	\N	\N	\N	\N	\N	\N	\N	\N	\N	1	1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	\N
3	1	1	1018	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0	\N
4	1	1	1016	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	1	\N	101	101	\N	\N	\N	\N	\N	\N	\N	0	\N
5	1	1	1017	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	1	6	101	101	\N	\N	\N	\N	\N	\N	\N	0	\N
6	0	1	2	book	\N	\N	\N	\N	\N	\N	\N	\N	0	\N	1	\N	\N	\N	1	10	101	1	\N	\N	\N	\N	\N	\N	\N	0	\N
\.

\echo sequence update column: id
SELECT SETVAL('config.circ_matrix_matchpoint_id_seq', (SELECT MAX(id) FROM config.circ_matrix_matchpoint));
