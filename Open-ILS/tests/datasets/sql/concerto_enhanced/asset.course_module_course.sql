COPY asset.course_module_course (id, name, course_number, section_number, owning_lib, is_archived) FROM stdin;
1	History of Indonesia	HST243	\N	1	0
\.

\echo sequence update column: id
SELECT SETVAL('asset.course_module_course_id_seq', (SELECT MAX(id) FROM asset.course_module_course));
