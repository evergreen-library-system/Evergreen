COPY asset.course_module_course_materials (id, course, item, relationship, record, temporary_record, original_location, original_status, original_circ_modifier, original_callnumber, original_circ_lib) FROM stdin;
1	1	\N	Required	200	\N	\N	\N	\N	\N	\N
2	1	\N	Optional	201	\N	\N	\N	\N	\N	\N
\.

\echo sequence update column: id
SELECT SETVAL('asset.course_module_course_materials_id_seq', (SELECT MAX(id) FROM asset.course_module_course_materials));
