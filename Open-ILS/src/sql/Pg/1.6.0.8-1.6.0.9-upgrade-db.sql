/*
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

INSERT INTO config.upgrade_log(version) VALUES ('1.6.0.9');

CREATE OR REPLACE FUNCTION oils_text_as_bytea (TEXT) RETURNS BYTEA AS $_$
    SELECT CAST(REGEXP_REPLACE($1, $$\\$$, $$\\\\$$, 'g') AS BYTEA);
$_$ LANGUAGE SQL IMMUTABLE;

DROP INDEX asset.asset_call_number_upper_label_id_owning_lib_idx;
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (oils_text_as_bytea(upper(label)),id,owning_lib);

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
    ARRAY_ACCUM( DISTINCT SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
    ARRAY_ACCUM( DISTINCT SUBSTRING(REGEXP_REPLACE(issn.value, E'^\\s*(\\d{4})[-\\s](\\d{3,4}x?)\\s*', E'\\1 \\2') FROM 1 FOR 9) ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

COMMIT;
