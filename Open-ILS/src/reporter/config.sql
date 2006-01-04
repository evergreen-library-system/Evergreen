DROP SCHEMA reporter CASCADE;

CREATE SCHEMA reporter;

BEGIN;

CREATE OR REPLACE VIEW reporter.date_series AS
	SELECT	CAST('1900/01/01' AS DATE) + x AS date,
		CAST('1900/01/01' AS DATE) + x AS date_label
	  FROM	GENERATE_SERIES(
	  		0,
	  		CAST( EXTRACT( 'days' FROM CAST( NOW() - CAST( '1900/01/01' AS DATE ) AS INTERVAL ) ) AS INT )
		) AS g(x);

CREATE OR REPLACE VIEW reporter.date_hour_series AS
	SELECT	CAST(date + CAST(h || ' hours' AS INTERVAL) AS TIMESTAMP WITH TIME ZONE) AS date_hour,
		CAST(date + CAST(h || ' hours' AS INTERVAL) AS TIMESTAMP WITH TIME ZONE) AS date_hour_label
	  FROM	reporter.date_series,
	  	GENERATE_SERIES(0,23) g(h);



CREATE TABLE reporter.date_dim AS
        SELECT 
                EXTRACT('year' FROM date_label)::INT AS year,
                EXTRACT('month' FROM date_label)::INT AS month,
                EXTRACT('day' FROM date_label)::INT AS day
        FROM
                (SELECT '1900-01-01'::date + g.x AS date_label
                   FROM GENERATE_SERIES(0, EXTRACT('days' FROM NOW() + '10 years'::INTERVAL - '1900-01-01'::TIMESTAMP WITH TIME ZONE)::INT) g(x)) as y
        ORDER BY 1,2,3;


CREATE TABLE reporter.time_dim AS
        SELECT 
                a.x AS hour,     
                b.x AS minute, 
                c.x AS second
        FROM
                   GENERATE_SERIES(0, 23) as a(x),
                   GENERATE_SERIES(0, 59) as b(x),
                   GENERATE_SERIES(0, 59) as c(x)
        order by 1,2,3;


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
	disable		bool				not null
							default false,
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

