DROP SCHEMA action CASCADE;

BEGIN;

CREATE SCHEMA action;

CREATE TABLE action.survey (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	start_date	DATE	NOT NULL DEFAULT NOW(),
	end_date	DATE	NOT NULL DEFAULT NOW() + '10 years'::INTERVAL,
	usr_summary	BOOL	NOT NULL DEFAULT FALSE,
	opac		BOOL	NOT NULL DEFAULT FALSE
);

CREATE TABLE action.survey_question (
	id		SERIAL	PRIMARY KEY,
	survey		INT	NOT NULL REFERENCES action.survey,
	question	TEXT	NOT NULL UNIQUE
);

CREATE TABLE action.survey_answer (
	id		SERIAL	PRIMARY KEY,
	question	INT	NOT NULL REFERENCES action.survey_question,
	answer		TEXT	NOT NULL UNIQUE
);

CREATE TABLE action.survey_response (
	id		BIGSERIAL	PRIMARY KEY,
	usr		BIGINT		NOT NULL, -- REFERENCES actor.usr
	survey		INT		NOT NULL REFERENCES action.survey,
	question	INT		NOT NULL REFERENCES action.survey_question,
	answer		INT		NOT NULL REFERENCES action.survey_answer,
	answer_date	DATE,
	effective_date	DATE		NOT NULL DEFAULT NOW()::DATE
);
CREATE FUNCTION action.survey_response_answer_date_fixup () RETURNS TRIGGER AS $$
BEGIN
	NEW.anser_date := NOW()::DATE;
	RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';
CREATE TRIGGER action_survey_response_answer_date_fixup_tgr
	BEFORE INSERT ON action.survey_response
	FOR EACH ROW
	EXECUTE PROCEDURE action.survey_response_answer_date_fixup ();

COMMIT;
	
