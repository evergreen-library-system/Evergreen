COPY action.survey_answer (id, question, answer) FROM stdin;
1	1	My name is Sir Lancelot of Camelot.
2	1	Sir Robin of Camelot.
3	1	Sir Galahad of Camelot.
4	1	General Leia Organa.
5	1	Dr. Beverly Crusher.
6	1	Rose Tyler.
7	1	Sorry, not interested.
8	2	To seek the Holy Grail.
9	2	To go where no one has gone before.
10	2	To steal the plans for the Death Star.
11	2	To save the universe from the Daleks again.
12	2	What is this again?
13	3	Blue
14	3	Blue. No yellow... AAAGGH!
15	3	Jedi cloak brown.
16	3	Redshirt red.
17	3	TARDIS blue.
18	3	This is getting too silly - I quit.
\.

\echo sequence update column: id
SELECT SETVAL('action.survey_answer_id_seq', (SELECT MAX(id) FROM action.survey_answer));
