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
CREATE UNIQUE INDEX rpt_template_folder_once_parent_idx ON reporter.template_folder (name,parent);
CREATE UNIQUE INDEX rpt_template_folder_once_idx ON reporter.template_folder (name,owner) WHERE parent IS NULL;

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
CREATE UNIQUE INDEX rpt_report_folder_once_parent_idx ON reporter.report_folder (name,parent);
CREATE UNIQUE INDEX rpt_report_folder_once_idx ON reporter.report_folder (name,owner) WHERE parent IS NULL;

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
CREATE UNIQUE INDEX rpt_output_folder_once_parent_idx ON reporter.output_folder (name,parent);
CREATE UNIQUE INDEX rpt_output_folder_once_idx ON reporter.output_folder (name,owner) WHERE parent IS NULL;


CREATE TABLE reporter.template (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	name		TEXT				NOT NULL,
	description	TEXT				NOT NULL,
	data		TEXT				NOT NULL,
	folder		INT				NOT NULL REFERENCES reporter.template_folder (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX rpt_tmpl_owner_idx ON reporter.template (owner);
CREATE INDEX rpt_tmpl_fldr_idx ON reporter.template (folder);
CREATE UNIQUE INDEX rtp_template_folder_once_idx ON reporter.template (name,folder);

CREATE TABLE reporter.report (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	name		TEXT				NOT NULL DEFAULT '',
	description	TEXT				NOT NULL DEFAULT '',
	template	INT				NOT NULL REFERENCES reporter.template (id) DEFERRABLE INITIALLY DEFERRED,
	data		TEXT				NOT NULL,
	folder		INT				NOT NULL REFERENCES reporter.report_folder (id) DEFERRABLE INITIALLY DEFERRED,
	recur		BOOL				NOT NULL DEFAULT FALSE,
	recurance	INTERVAL
);
CREATE INDEX rpt_rpt_owner_idx ON reporter.report (owner);
CREATE INDEX rpt_rpt_fldr_idx ON reporter.report (folder);
CREATE UNIQUE INDEX rtp_report_folder_once_idx ON reporter.report (name,folder);

CREATE TABLE reporter.schedule (
	id		SERIAL				PRIMARY KEY,
	report		INT				NOT NULL REFERENCES reporter.report (id) DEFERRABLE INITIALLY DEFERRED,
	folder		INT				NOT NULL REFERENCES reporter.output_folder (id) DEFERRABLE INITIALLY DEFERRED,
	runner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	run_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	start_time	TIMESTAMP WITH TIME ZONE,
	complete_time	TIMESTAMP WITH TIME ZONE,
	email		TEXT,
	excel_format	BOOL				NOT NULL DEFAULT TRUE,
	html_format	BOOL				NOT NULL DEFAULT TRUE,
	csv_format	BOOL				NOT NULL DEFAULT TRUE,
	chart_pie	BOOL				NOT NULL DEFAULT FALSE,
	chart_bar	BOOL				NOT NULL DEFAULT FALSE,
	chart_line	BOOL				NOT NULL DEFAULT FALSE,
	error_code	INT,
	error_text	TEXT
);
CREATE INDEX rpt_sched_runner_idx ON reporter.schedule (runner);
CREATE INDEX rpt_sched_folder_idx ON reporter.schedule (folder);

CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT	r.id,
	s.metarecord,
	r.fingerprint,
	r.quality,
	r.tcn_source,
	r.tcn_value,
	title.value AS title,
	uniform_title.value AS uniform_title,
	author.value AS author,
	publisher.value AS publisher,
	SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
	series_title.value AS series_title,
	series_statement.value AS series_statement,
	summary.value AS summary,
	ARRAY_ACCUM( SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
	ARRAY_ACCUM( SUBSTRING(issn.value FROM $$^\S+$$) ) AS issn,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
	ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM	biblio.record_entry r
	JOIN metabib.metarecord_source_map s ON (s.source = r.id)
	LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
	LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
	LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
	LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT	r.id,
	r.fingerprint,
	r.quality,
	r.tcn_source,
	r.tcn_value,
	title.value AS title,
	FIRST(author.value) AS author,
	publisher.value AS publisher,
	SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
	ARRAY_ACCUM( SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
	ARRAY_ACCUM( SUBSTRING(issn.value FROM $$^\S+$$) ) AS issn
  FROM	biblio.record_entry r
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,8,9;

CREATE TABLE reporter.materialized_simple_record AS SELECT * FROM reporter.old_super_simple_record WHERE 1=0;
ALTER TABLE reporter.materialized_simple_record ADD PRIMARY KEY (id);

CREATE VIEW reporter.super_simple_record AS SELECT * FROM reporter.materialized_simple_record;

CREATE OR REPLACE FUNCTION reporter.simple_rec_sync () RETURNS TRIGGER AS $$
DECLARE
    r_id        BIGINT;
    new_data    RECORD;
BEGIN
    IF TG_OP IN ('DELETE') THEN
        r_id := OLD.record;
    ELSE
        r_id := NEW.record;
    END IF;

    SELECT * INTO new_data FROM reporter.materialized_simple_record WHERE id = r_id FOR UPDATE;
    DELETE FROM reporter.materialized_simple_record WHERE id = r_id;

    IF TG_OP IN ('DELETE') THEN
        RETURN OLD;
    ELSE
        INSERT INTO reporter.materialized_simple_record SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record WHERE id = NEW.record;
        RETURN NEW;
    END IF;

END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER zzz_update_materialized_simple_record_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.full_rec
    FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_sync();

CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DROP TRIGGER zzz_update_materialized_simple_record_tgr ON metabib.full_rec;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    TRUNCATE TABLE reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER zzz_update_materialized_simple_record_tgr
        AFTER INSERT OR UPDATE OR DELETE ON metabib.full_rec
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_sync();

$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.refresh_materialized_simple_record () RETURNS VOID AS $$
    SELECT reporter.disable_materialized_simple_record_trigger();
    SELECT reporter.enable_materialized_simple_record_trigger();
$$ LANGUAGE SQL;

CREATE OR REPLACE VIEW reporter.demographic AS
SELECT	u.id,
	u.dob,
	CASE
		WHEN u.dob IS NULL
			THEN 'Adult'
		WHEN AGE(u.dob) > '18 years'::INTERVAL
			THEN 'Adult'
		ELSE 'Juvenile'
	END AS general_division
  FROM	actor.usr u;

CREATE OR REPLACE VIEW reporter.circ_type AS
SELECT	id,
	CASE WHEN opac_renewal OR phone_renewal OR desk_renewal
		THEN 'RENEWAL'
		ELSE 'CHECKOUT'
	END AS "type"
  FROM	action.circulation;

CREATE OR REPLACE VIEW reporter.hold_request_record AS
SELECT	id,
	target,
	hold_type,
	CASE
		WHEN hold_type = 'T'
			THEN target
		WHEN hold_type = 'V'
			THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = ahr.target)
		WHEN hold_type = 'C'
			THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = ahr.target)
		WHEN hold_type = 'M'
			THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = ahr.target)
	END AS bib_record
  FROM	action.hold_request ahr;

CREATE OR REPLACE VIEW reporter.xact_billing_totals AS
SELECT	b.xact,
	SUM( CASE WHEN b.voided THEN 0 ELSE amount END ) as unvoided,
	SUM( CASE WHEN b.voided THEN amount ELSE 0 END ) as voided,
	SUM( amount ) as total
  FROM	money.billing b
  GROUP BY 1;

CREATE OR REPLACE VIEW reporter.xact_paid_totals AS
SELECT	b.xact,
	SUM( CASE WHEN b.voided THEN 0 ELSE amount END ) as unvoided,
	SUM( CASE WHEN b.voided THEN amount ELSE 0 END ) as voided,
	SUM( amount ) as total
  FROM	money.payment b
  GROUP BY 1;

CREATE OR REPLACE VIEW reporter.overdue_circs AS
SELECT  *
  FROM  "action".circulation
  WHERE checkin_time is null
        AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED') OR stop_fines IS NULL)
        AND due_date < now();

CREATE OR REPLACE VIEW reporter.overdue_reports AS
 SELECT s.id, c.barcode AS runner_barcode, r.name, s.run_time, s.run_time - now() AS scheduled_wait_time
   FROM reporter.schedule s
   JOIN reporter.report r ON r.id = s.report
   JOIN actor.usr u ON s.runner = u.id
   JOIN actor.card c ON c.id = u.card
  WHERE s.start_time IS NULL AND s.run_time < now();

CREATE OR REPLACE VIEW reporter.pending_reports AS
 SELECT s.id, c.barcode AS runner_barcode, r.name, s.run_time, s.run_time - now() AS scheduled_wait_time
   FROM reporter.schedule s
   JOIN reporter.report r ON r.id = s.report
   JOIN actor.usr u ON s.runner = u.id
   JOIN actor.card c ON c.id = u.card
  WHERE s.start_time IS NULL;

CREATE OR REPLACE VIEW reporter.currently_running AS
 SELECT s.id, c.barcode AS runner_barcode, r.name, s.run_time, s.run_time - now() AS scheduled_wait_time
   FROM reporter.schedule s
   JOIN reporter.report r ON r.id = s.report
   JOIN actor.usr u ON s.runner = u.id
   JOIN actor.card c ON c.id = u.card
  WHERE s.start_time IS NOT NULL AND s.complete_time IS NULL;

COMMIT;

