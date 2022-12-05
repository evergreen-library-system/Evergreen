COPY action.survey_question (id, survey, question) FROM stdin;
1	1	What... is your name?
2	1	What... is your quest?
3	1	What... is your favorite color?
\.

\echo sequence update column: id
SELECT SETVAL('action.survey_question_id_seq', (SELECT MAX(id) FROM action.survey_question));
