/*
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 * Copyright (C) 2010  Equinox Software, Inc.
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

BEGIN;

INSERT INTO config.upgrade_log(version) VALUES ('1.6.0.4');

-- Match ingest fixes for leading / trailing whitespace on ISSNs and date ranges
UPDATE metabib.real_full_rec
    SET value = TRIM(value)
    WHERE (tag = '022' AND subfield = 'a')
        OR (tag = '100' AND subfield = 'd')
;

-- Correct reporter view definitions for ISSNs now that they contain spaces instead of hyphens
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
	ARRAY_ACCUM( DISTINCT SUBSTRING(REGEXP_REPLACE(issn.value, E'^\\s*(\\d{4})[-\\s](\\d{3,4}x?)\\s*', E'\\1 \\2') FROM 1 FOR 9)) AS issn,
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
	ARRAY_ACCUM( DISTINCT SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
	ARRAY_ACCUM( DISTINCT SUBSTRING(REGEXP_REPLACE(issn.value, E'^\\s*(\\d{4})[-\\s](\\d{3,4}x?)\\s*', E'\\1 \\2') FROM 1 FOR 9) ) AS issn
  FROM biblio.record_entry r
	LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
	LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
	LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
	LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
	LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
	LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,8,9;

-- Now rebuild the materialized simple record table that was built on reporter.old_super_simple_record
TRUNCATE TABLE materialized.simple_record;
INSERT INTO materialized.simple_record
    SELECT * FROM reporter.old_super_simple_record;

-- Replace the billable transaction summary view with one that is more cautious about NULL values
CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id,
		xact.usr,
		xact.xact_start,
		xact.xact_finish,
		COALESCE(credit.amount, 0.0::numeric) AS total_paid,
		credit.payment_ts AS last_payment_ts,
		credit.note AS last_payment_note,
		credit.payment_type AS last_payment_type,
		COALESCE(debit.amount, 0.0::numeric) AS total_owed,
		debit.billing_ts AS last_billing_ts,
		debit.note AS last_billing_note,
		debit.billing_type AS last_billing_type,
		COALESCE(debit.amount, 0.0::numeric) - COALESCE(credit.amount, 0.0::numeric) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
		JOIN pg_class p ON xact.tableoid = p.oid
		LEFT JOIN (
			SELECT	billing.xact,
				sum(billing.amount) AS amount,
				max(billing.billing_ts) AS billing_ts,
				last(billing.note) AS note,
				last(billing.billing_type) AS billing_type
			  FROM	money.billing
			  WHERE	billing.voided IS FALSE
			  GROUP BY billing.xact
			) debit ON xact.id = debit.xact
		LEFT JOIN (
			SELECT	payment_view.xact,
				sum(payment_view.amount) AS amount,
				max(payment_view.payment_ts) AS payment_ts,
				last(payment_view.note) AS note,
				last(payment_view.payment_type) AS payment_type
			  FROM	money.payment_view
			  WHERE	payment_view.voided IS FALSE
			  GROUP BY payment_view.xact
			) credit ON xact.id = credit.xact
	  ORDER BY debit.billing_ts, credit.payment_ts;

-- And rebuild the materialized view that was built on money.billable_xact_summary
TRUNCATE TABLE money.materialized_billable_xact_summary;
INSERT INTO TABLE money.materialized_billable_xact_summary
	SELECT * FROM money.billable_xact_summary;

COMMIT;

-- More trigger event definition permissions
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_CLEANUP', 'Allow a user to create, delete, and update trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_CLEANUP', 'Allow a user to create trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_CLEANUP', 'Allow a user to delete trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_CLEANUP', 'Allow a user to update trigger cleanup entries');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_EVENT_DEF', 'Allow a user to create trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_EVENT_DEF', 'Allow a user to delete trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_EVENT_DEF', 'Allow a user to update trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('VIEW_TRIGGER_EVENT_DEF', 'Allow a user to view trigger event definitions');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_HOOK', 'Allow a user to create, update, and delete trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_HOOK', 'Allow a user to create trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_HOOK', 'Allow a user to delete trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_HOOK', 'Allow a user to update trigger hooks');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_REACTOR', 'Allow a user to create, update, and delete trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_REACTOR', 'Allow a user to create trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_REACTOR', 'Allow a user to delete trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_REACTOR', 'Allow a user to update trigger reactors');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_TEMPLATE_OUTPUT', 'Allow a user to delete trigger template output');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_TEMPLATE_OUTPUT', 'Allow a user to delete trigger template output');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_TRIGGER_VALIDATOR', 'Allow a user to create, update, and delete trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('CREATE_TRIGGER_VALIDATOR', 'Allow a user to create trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('DELETE_TRIGGER_VALIDATOR', 'Allow a user to delete trigger validators');
INSERT INTO permission.perm_list (code, description) VALUES ('UPDATE_TRIGGER_VALIDATOR', 'Allow a user to update trigger validators';

-- Add trigger administration permissions to the Local System Administrator group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 1, false FROM permission.perm_list
        WHERE code LIKE 'ADMIN_TRIGGER%'
            OR code LIKE 'CREATE_TRIGGER%'
            OR code LIKE 'DELETE_TRIGGER%'
            OR code LIKE 'UPDATE_TRIGGER%'
;
-- View trigger permissions are required at a consortial level for initial setup
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 0, false FROM permission.perm_list WHERE code LIKE 'VIEW_TRIGGER%';


