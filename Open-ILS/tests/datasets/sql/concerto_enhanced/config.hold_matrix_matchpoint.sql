COPY config.hold_matrix_matchpoint (id, active, strict_ou_match, user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, usr_grp, requestor_grp, circ_modifier, marc_type, marc_form, marc_bib_level, marc_vr_format, juvenile_flag, ref_flag, item_age, holdable, distance_is_from_owner, transit_range, max_holds, include_frozen_holds, stop_blocked_user, age_hold_protect_rule, description) FROM stdin;
3	1	0	\N	\N	\N	\N	\N	\N	1018	\N	\N	\N	\N	\N	\N	0	\N	0	0	\N	\N	0	0	\N	No holds for Digital Patrons
4	1	0	\N	\N	\N	\N	\N	\N	1	bestseller no hold	\N	\N	\N	\N	\N	0	\N	0	0	\N	\N	0	0	\N	\N
\.

\echo sequence update column: id
SELECT SETVAL('config.hold_matrix_matchpoint_id_seq', (SELECT MAX(id) FROM config.hold_matrix_matchpoint));
