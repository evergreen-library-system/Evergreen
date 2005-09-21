DROP SCHEMA reporter CASCADE;

CREATE SCHEMA reporter;

BEGIN;

CREATE TABLE reporter.stage1 (
	id		serial				primary key,
	filename	text				not null,
	owner		int				not null,
	pub		bool				not null
							default true,
	create_date	timestamp with time zone	not null
							default now(),
	edit_date	timestamp with time zone	not null
							default now()
);

CREATE TABLE reporter.stage2 (
	id		serial				primary key,
	stage1		int				not null 
							references reporter.stage1 (id)
								on delete restrict
								deferrable
								initially deferred,
	filename	text				not null,
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
	filename	text				not null,
	owner		int				not null,
	pub		bool				not null
							default false,
	create_date	timestamp with time zone	not null
							default now()
);

COMMIT;

