DROP SCHEMA reporter CASCADE;

BEGIN;

CREATE SCHEMA reporter;

CREATE TABLE reporter.template_folder (
	id		SERIAL				PRIMARY KEY,
	parent		INT				REFERENCES reporter.template_folder (id) DEFERRABLE INITIALLY DEFERRED,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	name		TEXT				NOT NULL,
	shared		BOOL				NOT NULL DEFAULT FALSE,
	share_with	INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX rpt_tmpl_fldr_owner_idx ON reporter.template_folder (owner);

CREATE TABLE reporter.report_folder (
	id		SERIAL				PRIMARY KEY,
	parent		INT				REFERENCES reporter.report_folder (id) DEFERRABLE INITIALLY DEFERRED,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	name		TEXT				NOT NULL,
	shared		BOOL				NOT NULL DEFAULT FALSE,
	share_with	INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX rpt_rpt_fldr_owner_idx ON reporter.report_folder (owner);

CREATE TABLE reporter.output_folder (
	id		SERIAL				PRIMARY KEY,
	parent		INT				REFERENCES reporter.output_folder (id) DEFERRABLE INITIALLY DEFERRED,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	name		TEXT				NOT NULL,
	shared		BOOL				NOT NULL DEFAULT FALSE,
	share_with	INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX rpt_output_fldr_owner_idx ON reporter.output_folder (owner);


CREATE TABLE reporter.template (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	name		TEXT				NOT NULL,
	description	TEXT				NOT NULL,
	data		TEXT				NOT NULL,
	folder		INT				NOT NULL REFERENCES reporter.template_folder (id)
);
CREATE INDEX rpt_tmpl_owner_idx ON reporter.template (owner);
CREATE INDEX rpt_tmpl_fldr_idx ON reporter.template (folder);

CREATE TABLE reporter.report (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	template	INT				NOT NULL REFERENCES reporter.template (id) DEFERRABLE INITIALLY DEFERRED,
	data		TEXT				NOT NULL,
	folder		INT				NOT NULL REFERENCES reporter.report_folder (id),
	recur		BOOL				NOT NULL DEFAULT FALSE,
	recurance	INTERVAL
);
CREATE INDEX rpt_rpt_owner_idx ON reporter.report (owner);
CREATE INDEX rpt_rpt_fldr_idx ON reporter.report (folder);

CREATE TABLE reporter.schedule (
	id		SERIAL				PRIMARY KEY,
	report		INT				NOT NULL REFERENCES reporter.report (id) DEFERRABLE INITIALLY DEFERRED,
	folder		INT				NOT NULL REFERENCES reporter.output_folder (id),
	runner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	run_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	start_time	TIMESTAMP WITH TIME ZONE,
	complete_time	TIMESTAMP WITH TIME ZONE,
	email		TEXT,
	excel_format	BOOL				NOT NULL DEFAULT TRUE,
	html_format	BOOL				NOT NULL DEFAULT TRUE,
	csv_format	BOOL				NOT NULL DEFAULT TRUE,
	error_code	INT,
	error_text	TEXT
);
CREATE INDEX rpt_sched_runner_idx ON reporter.schedule (runner);
CREATE INDEX rpt_sched_folder_idx ON reporter.schedule (folder);

COMMIT;

