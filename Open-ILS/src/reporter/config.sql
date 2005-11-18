DROP SCHEMA reporter CASCADE;

CREATE SCHEMA reporter;

BEGIN;

CREATE TABLE reporter.stage2 (
	id		serial				primary key,
	stage1		text				not null, 
	params	  	text				not null,
	owner		int				not null,
	pub		bool				not null
							default false,
	create_date	timestamp with time zone	not null
							default now(),
	edit_date	timestamp with time zone	not null
							default now()
);

CREATE OR REPLACE FUNCTION reporter.force_edit_date_update () RETURNS TRIGGER AS $$
	BEGIN
		NEW.edit_date = NOW();
		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER force_edit_date_update_trig
	BEFORE UPDATE ON reporter.stage2
	FOR EACH ROW
	EXECUTE PROCEDURE reporter.force_edit_date_update ();

CREATE TABLE reporter.stage3 (
	id		serial				primary key,
	stage2		int				not null 
							references reporter.stage2 (id)
								on delete restrict
								deferrable
								initially deferred,
	params	  	text				not null,
	owner		int				not null,
	pub		bool				not null
							default false,
	create_date	timestamp with time zone	not null
							default now(),
	runtime	timestamp with time zone	default now(),
	recurrence	interval
);

CREATE TABLE reporter.output (
	id		serial				primary key,
	stage3		int				not null
							references reporter.stage3 (id)
								on delete restrict
								deferrable
								initially deferred,
	queue_time	timestamp with time zone	not null default now(),
	run_time	timestamp with time zone,
	run_pid		int,
	query		text,
	error		text,
	error_time	timestamp with time zone,
	complete_time	timestamp with time zone,
	state		text				check (state in ('wait','running','complete','error'))
);

COMMIT;

