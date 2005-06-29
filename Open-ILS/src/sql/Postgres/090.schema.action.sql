DROP SCHEMA action CASCADE;

BEGIN;

CREATE SCHEMA action;

CREATE TABLE action.survey (
	id		SERIAL	PRIMARY KEY,
	owner		INT	NOT NULL REFERENCES actor.org_unit (id),
	name		TEXT	NOT NULL,
	description	TEXT	NOT NULL,
	start_date	DATE	NOT NULL DEFAULT NOW(),
	end_date	DATE	NOT NULL DEFAULT NOW() + '10 years'::INTERVAL,
	usr_summary	BOOL	NOT NULL DEFAULT FALSE,
	opac		BOOL	NOT NULL DEFAULT FALSE,
	poll		BOOL	NOT NULL DEFAULT FALSE,
	required	BOOL	NOT NULL DEFAULT FALSE
);
CREATE UNIQUE INDEX asv_once_per_owner_idx ON action.survey (owner,name);

CREATE TABLE action.survey_question (
	id		SERIAL	PRIMARY KEY,
	survey		INT	NOT NULL REFERENCES action.survey,
	question	TEXT	NOT NULL
);

CREATE TABLE action.survey_answer (
	id		SERIAL	PRIMARY KEY,
	question	INT	NOT NULL REFERENCES action.survey_question,
	answer		TEXT	NOT NULL
);

CREATE SEQUENCE action.survey_response_group_id_seq;

CREATE TABLE action.survey_response (
	id			BIGSERIAL			PRIMARY KEY,
	response_group_id	INT,
	usr			INT, -- REFERENCES actor.usr
	survey			INT				NOT NULL REFERENCES action.survey,
	question		INT				NOT NULL REFERENCES action.survey_question,
	answer			INT				NOT NULL REFERENCES action.survey_answer,
	answer_date		TIMESTAMP WITH TIME ZONE,
	effective_date		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE OR REPLACE FUNCTION action.survey_response_answer_date_fixup () RETURNS TRIGGER AS '
BEGIN
	NEW.answer_date := NOW();
	RETURN NEW;
END;
' LANGUAGE 'plpgsql';
CREATE TRIGGER action_survey_response_answer_date_fixup_tgr
	BEFORE INSERT ON action.survey_response
	FOR EACH ROW
	EXECUTE PROCEDURE action.survey_response_answer_date_fixup ();


CREATE TABLE action.circulation (
	target_copy		BIGINT				NOT NULL, -- asset.copy.id
	circ_lib		INT				NOT NULL, -- actor.org_unit.id
	duration_rule		TEXT				NOT NULL, -- name of "circ duration" rule
	duration		INTERVAL			NOT NULL, -- derived from "circ duration" rule
	renewal_remaining	INT				NOT NULL, -- derived from "circ duration" rule
	recuring_fine_rule	TEXT				NOT NULL, -- name of "circ fine" rule
	recuring_fine		NUMERIC(6,2)			NOT NULL, -- derived from "circ fine" rule
	max_fine_rule		TEXT				NOT NULL, -- name of "max fine" rule
	max_fine		NUMERIC(6,2)			NOT NULL, -- derived from "max fine" rule
	fine_interval		INTERVAL			NOT NULL DEFAULT '1 day'::INTERVAL, -- derived from "circ fine" rule
	due_date		TIMESTAMP WITH TIME ZONE	NOT NULL,
	stop_fines		TEXT				CHECK (stop_fines IN ('CHECKIN','CLAIMSRETURNED','LOST','MAXFINES'))
) INHERITS (money.billable_xact);
CREATE INDEX circ_open_xacts_idx ON action.circulation (usr) WHERE xact_finish IS NULL;


CREATE TABLE action.hold_request (
	id			SERIAL				PRIMARY KEY,
	request_time		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	capture_time		TIMESTAMP WITH TIME ZONE,
	fulfillment_time	TIMESTAMP WITH TIME ZONE,
	prev_check_time		TIMESTAMP WITH TIME ZONE,
	expire_time		TIMESTAMP WITH TIME ZONE,
	requestor		INT				NOT NULL REFERENCES actor.usr (id),
	usr			INT				NOT NULL REFERENCES actor.usr (id),
	hold_type		CHAR				NOT NULL CHECK (hold_type IN ('M','T','V','C')),
	holdable_formats	TEXT,
	phone_notify		TEXT,
	email_notify		TEXT,
	target			BIGINT				NOT NULL, -- see hold_type
	selection_depth		INT				NOT NULL DEFAULT 0,
	pickup_lib		INT				NOT NULL REFERENCES actor.org_unit,
	current_copy		BIGINT				REFERENCES asset.copy (id) ON DELETE SET NULL
);


CREATE TABLE action.hold_notification (
	id		SERIAL				PRIMARY KEY,
	hold		INT				NOT NULL REFERENCES action.hold_request (id),
	method		TEXT				NOT NULL, -- eh...
	notify_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	note		TEXT
);

CREATE TABLE action.hold_copy_map (
	id		SERIAL	PRIMARY KEY,
	hold		INT	NOT NULL REFERENCES action.hold_notification (id) ON DELETE CASCADE,
	target_copy	BIGINT	NOT NULL REFERENCES asset.copy (id) ON DELETE CASCADE,
	CONSTRAINT copy_once_per_hold UNIQUE (hold,copy)
);


COMMIT;

