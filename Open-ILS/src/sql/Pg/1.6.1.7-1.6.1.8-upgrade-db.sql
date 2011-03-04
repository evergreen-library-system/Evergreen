/*
 * Copyright (C) 2011  Equinox Software, Inc.
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

INSERT INTO config.upgrade_log(version) VALUES ('1.6.1.8');

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS
    SELECT  xact.id AS id,
        xact.usr AS usr,
        COALESCE(circ.circ_lib,groc.billing_location,res.pickup_lib) AS billing_location,
        xact.xact_start AS xact_start,
        xact.xact_finish AS xact_finish,
        SUM(credit.amount) AS total_paid,
        MAX(credit.payment_ts) AS last_payment_ts,
        LAST(credit.note) AS last_payment_note,
        LAST(credit.payment_type) AS last_payment_type,
        SUM(debit.amount) AS total_owed,
        MAX(debit.billing_ts) AS last_billing_ts,
        LAST(debit.note) AS last_billing_note,
        LAST(debit.billing_type) AS last_billing_type,
        COALESCE(SUM(debit.amount),0) - COALESCE(SUM(credit.amount),0) AS balance_owed,
        p.relname AS xact_type
      FROM  money.billable_xact xact
        JOIN pg_class p ON (xact.tableoid = p.oid)
        LEFT JOIN "action".circulation circ ON (circ.id = xact.id)
        LEFT JOIN money.grocery groc ON (groc.id = xact.id)
        LEFT JOIN booking.reservation res ON (res.id = xact.id)
        LEFT JOIN (
            SELECT  billing.xact,
                billing.voided,
                sum(billing.amount) AS amount,
                max(billing.billing_ts) AS billing_ts,
                last(billing.note) AS note,
                last(billing.billing_type) AS billing_type
              FROM  money.billing
              WHERE billing.voided IS FALSE
              GROUP BY billing.xact, billing.voided
        ) debit ON (xact.id = debit.xact AND debit.voided IS FALSE)
        LEFT JOIN (
            SELECT  payment_view.xact,
                payment_view.voided,
                sum(payment_view.amount) AS amount,
                max(payment_view.payment_ts) AS payment_ts,
                last(payment_view.note) AS note,
                last(payment_view.payment_type) AS payment_type
              FROM  money.payment_view
              WHERE payment_view.voided IS FALSE
              GROUP BY payment_view.xact, payment_view.voided
        ) credit ON (xact.id = credit.xact AND credit.voided IS FALSE)
      WHERE xact.xact_finish IS NULL
      GROUP BY 1,2,3,4,5,15
      ORDER BY MAX(debit.billing_ts), MAX(credit.payment_ts);

CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT  r.id,
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
    ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
    ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y
') THEN 0 ELSE 1 END)) AS external_uri
  FROM  biblio.record_entry r
    JOIN metabib.metarecord_source_map s ON (s.source = r.id)
    LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
    LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
    LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a
')
    LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT publisher.value), ', ') AS publisher,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$) ), ', ') AS pubdate,
    ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

