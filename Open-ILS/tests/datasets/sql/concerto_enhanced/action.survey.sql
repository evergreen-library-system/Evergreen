COPY action.survey (id, owner, start_date, end_date, usr_summary, opac, poll, required, name, description) FROM stdin;
1	1	2020-10-27 10:26:51.426709-04	2030-10-27 10:26:51.426709-04	0	0	0	0	Who would cross the Bridge of Death must answer me these questions three, ere the other side he see.	Test survey for concerto dataset
\.

\echo sequence update column: id
SELECT SETVAL('action.survey_id_seq', (SELECT MAX(id) FROM action.survey));
