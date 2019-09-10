/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

DROP SCHEMA IF EXISTS reporter CASCADE;

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
	description	TEXT				NOT NULL DEFAULT '',
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
	recurrence	INTERVAL
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
	ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
	ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
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
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
	LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
	LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
	LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    evergreen.oils_json_to_text(d.title) AS title,
    evergreen.oils_json_to_text(d.author) AS author,
    evergreen.oils_json_to_text(d.publisher) AS publisher,
    evergreen.oils_json_to_text(d.pubdate) AS pubdate,
    CASE WHEN d.isbn = 'null'
        THEN NULL
        ELSE (SELECT ARRAY(SELECT json_array_elements_text(d.isbn::JSON)))
    END AS isbn,
    CASE WHEN d.issn = 'null'
        THEN NULL
        ELSE (SELECT ARRAY(SELECT json_array_elements_text(d.issn::JSON)))
    END AS issn
  FROM  biblio.record_entry r
        JOIN metabib.wide_display_entry d ON (r.id = d.source);

CREATE TABLE reporter.materialized_simple_record AS SELECT * FROM reporter.old_super_simple_record WHERE 1=0;
ALTER TABLE reporter.materialized_simple_record ADD PRIMARY KEY (id);

CREATE VIEW reporter.super_simple_record AS SELECT * FROM reporter.materialized_simple_record;

CREATE OR REPLACE FUNCTION reporter.simple_rec_update (r_id BIGINT, deleted BOOL) RETURNS BOOL AS $$
BEGIN

    DELETE FROM reporter.materialized_simple_record WHERE id = r_id;

    IF NOT deleted THEN
        INSERT INTO reporter.materialized_simple_record SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record WHERE id = r_id;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_update (r_id BIGINT) RETURNS BOOL AS $$
    SELECT reporter.simple_rec_update($1, FALSE);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_delete (r_id BIGINT) RETURNS BOOL AS $$
    SELECT reporter.simple_rec_update($1, TRUE);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_trigger () RETURNS TRIGGER AS $func$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM reporter.simple_rec_delete(NEW.id);
    ELSE
        PERFORM reporter.simple_rec_update(NEW.id);
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DROP TRIGGER IF EXISTS bbb_simple_rec_trigger ON biblio.record_entry;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    TRUNCATE TABLE reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER bbb_simple_rec_trigger
        AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger();

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
	CASE WHEN opac_renewal OR phone_renewal OR desk_renewal OR auto_renewal
		THEN 'RENEWAL'
		ELSE 'CHECKOUT'
	END AS "type"
  FROM	action.circulation;

-- rhrr needs to be a real table, so it can be fast. To that end, we use
-- a materialized view updated via a trigger.
CREATE TABLE reporter.hold_request_record  AS
SELECT  id,
        target,
        hold_type,
        CASE
                WHEN hold_type = 'T'
                        THEN target
                WHEN hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = ahr.target)
                WHEN hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = ahr.target)
                WHEN hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = ahr.target)
                WHEN hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = ahr.target)
                WHEN hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = ahr.target)
        END AS bib_record
  FROM  action.hold_request ahr;

CREATE UNIQUE INDEX reporter_hold_request_record_pkey_idx ON reporter.hold_request_record (id);
CREATE INDEX reporter_hold_request_record_bib_record_idx ON reporter.hold_request_record (bib_record);

ALTER TABLE reporter.hold_request_record ADD PRIMARY KEY USING INDEX reporter_hold_request_record_pkey_idx;

CREATE OR REPLACE FUNCTION reporter.hold_request_record_mapper () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO reporter.hold_request_record (id, target, hold_type, bib_record)
        SELECT  NEW.id,
                NEW.target,
                NEW.hold_type,
                CASE
                    WHEN NEW.hold_type = 'T'
                        THEN NEW.target
                    WHEN NEW.hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = NEW.target)
                    WHEN NEW.hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = NEW.target)
                    WHEN NEW.hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = NEW.target)
                    WHEN NEW.hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = NEW.target)
                    WHEN NEW.hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = NEW.target)
                END AS bib_record;
    ELSIF TG_OP = 'UPDATE' AND (OLD.target <> NEW.target OR OLD.hold_type <> NEW.hold_type) THEN
        UPDATE  reporter.hold_request_record
          SET   target = NEW.target,
                hold_type = NEW.hold_type,
                bib_record = CASE
                    WHEN NEW.hold_type = 'T'
                        THEN NEW.target
                    WHEN NEW.hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = NEW.target)
                    WHEN NEW.hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = NEW.target)
                    WHEN NEW.hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = NEW.target)
                    WHEN NEW.hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = NEW.target)
                    WHEN NEW.hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = NEW.target)
                END
         WHERE  id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER reporter_hold_request_record_trigger AFTER INSERT OR UPDATE ON action.hold_request
    FOR EACH ROW EXECUTE PROCEDURE reporter.hold_request_record_mapper();

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

