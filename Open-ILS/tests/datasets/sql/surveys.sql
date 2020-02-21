/** Create a survey */
INSERT INTO action.survey (id, owner, name, description) VALUES (1, 1, 'Who would cross the Bridge of Death must answer me these questions three, ere the other side he see.', 'Test survey for concerto dataset');

/** Populate with questions */
INSERT INTO action.survey_question (id, survey, question) VALUES (1, 1, 'What... is your name?');
INSERT INTO action.survey_question (id, survey, question) VALUES (2, 1, 'What... is your quest?');
INSERT INTO action.survey_question (id, survey, question) VALUES (3, 1, 'What... is your favorite color?');

/** Attach answers to questions */
INSERT INTO action.survey_answer (id, question, answer) VALUES (1, 1, 'My name is Sir Lancelot of Camelot.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (2, 1, 'Sir Robin of Camelot.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (3, 1, 'Sir Galahad of Camelot.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (4, 1, 'General Leia Organa.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (5, 1, 'Dr. Beverly Crusher.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (6, 1, 'Rose Tyler.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (7, 1, 'Sorry, not interested.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (8, 2, 'To seek the Holy Grail.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (9, 2, 'To go where no one has gone before.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (10, 2, 'To steal the plans for the Death Star.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (11, 2, 'To save the universe from the Daleks again.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (12, 2, 'What is this again?');
INSERT INTO action.survey_answer (id, question, answer) VALUES (13, 3, 'Blue');
INSERT INTO action.survey_answer (id, question, answer) VALUES (14, 3, 'Blue. No yellow... AAAGGH!');
INSERT INTO action.survey_answer (id, question, answer) VALUES (15, 3, 'Jedi cloak brown.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (16, 3, 'Redshirt red.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (17, 3, 'TARDIS blue.');
INSERT INTO action.survey_answer (id, question, answer) VALUES (18, 3, 'This is getting too silly - I quit.');

SELECT SETVAL('action.survey_id_seq'::TEXT, 100);
SELECT SETVAL('action.survey_question_id_seq'::TEXT, 100);
SELECT SETVAL('action.survey_answer_id_seq'::TEXT, 100);

/** for every user with an id not evenly divisible by 6, 
 *  add a randomized response for every question in the survey
 */
CREATE FUNCTION populate_survey_responses(usr INTEGER) RETURNS VOID AS
$BODY$
DECLARE q INT;
BEGIN
IF usr % 6 <> 0 THEN
    FOR q in 1..3 LOOP
        INSERT INTO action.survey_response (usr, survey, question, answer, answer_date) VALUES (
        usr,
        1,
        q,
        (SELECT id FROM action.survey_answer WHERE question = q ORDER BY random() LIMIT 1),
        now());
    END LOOP;
END IF;
END;
$BODY$
LANGUAGE plpgsql;

SELECT populate_survey_responses(id) FROM actor.usr;

DROP FUNCTION populate_survey_responses(usr INTEGER);
