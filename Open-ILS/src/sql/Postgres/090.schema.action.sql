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
	usr		INT		NOT NULL, -- REFERENCES actor.usr
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

CREATE TABLE action.circulation (
	target_copy		BIGINT		NOT NULL, -- asset.copy.id
	circ_lib		INT		NOT NULL, -- actor.org_unit.id
	duration_rule		TEXT		NOT NULL, -- name of "circ duration" rule
	duration		INTERVAL	NOT NULL, -- derived from "circ duration" rule
	renewal_remaining	INT		NOT NULL, -- derived from "circ duration" rule
	recuring_fine_rule	TEXT		NOT NULL, -- name of "circ fine" rule
	recuring_fine		NUMERIC(6,2)	NOT NULL, -- derived from "circ fine" rule
	max_fine_rule		TEXT		NOT NULL, -- name of "max fine" rule
	max_fine		NUMERIC(6,2)	NOT NULL, -- derived from "max fine" rule
	fine_interval		INTERVAL	NOT NULL DEFAULT '1 day'::INTERVAL, -- derived from "circ fine" rule
	stop_fines		TEXT		CHECK (stop_fines IN ('CHECKIN','CLAIMSRETURNED','LOST','MAXFINES'))
) INHERITS (money.billable_xact);
CREATE INDEX circ_open_xacts_idx ON action.circulation (usr) WHERE xact_finish IS NULL;


COMMIT;

